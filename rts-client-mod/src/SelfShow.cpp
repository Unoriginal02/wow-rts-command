#include "SelfShow.h"

#include <windows.h>
#include <cstring>

#include "CVarChannel.h"
#include "Log.h"
#include "Memory.h"
#include "ObjectManager.h"
#include "Offsets.h"

namespace selfshow {
namespace {

// Un CVar PROPIO, creado por el addon con RegisterCVar. Tomar prestado uno
// ajeno es lo que dejo el FOV muerto tres etapas: `guildMemberNotify` NO existe
// en este cliente y el canal fallaba en silencio. La cadena estaba en el
// binario, que es lo que lo hizo parecer buena eleccion; estar la cadena no es
// estar registrado el CVar.
constexpr const char* kProbeCVar = "rtsBody";

// Mascara de interruptores. 0 = inerte, que es el valor de fabrica.
constexpr int32_t kFlagsOn   = 1;   // escribir los dos flags cada tick
constexpr int32_t kFlagsOff  = 2;   // borrarlos cada tick (gana sobre kFlagsOn)
constexpr int32_t kSkipPatch = 4;   // anular el salto de 0x0073AAB0
constexpr int32_t kReport    = 8;   // una linea por segundo con lo que hay
constexpr int32_t kInvert    = 16;  // FORZAR el salto para TODAS las unidades
constexpr int32_t kUberOnly  = 32;  // solo el bit 19, y el 22 BORRADO
constexpr int32_t kCommOnly  = 64;  // solo el bit 22, y el 19 BORRADO

// EL DIAGNOSTICO DE "QUE SE LO TRAGUE TODO", QUE TENIA QUE HABER IDO PRIMERO.
//
// Anular el salto (kSkipPatch) NO devolvio el modelo del heroe -- visto en
// juego 2026-09-09, con el log confirmando el parche puesto. Eso admite dos
// explicaciones opuestas y mirando al heroe no se distinguen:
//
//   a) 0x0073A890 SI es la emision del modelo y el salto SI es su puerta, pero
//      hay una SEGUNDA puerta que tambien esconde al heroe.
//   b) 0x0073A890 no es lo que dibuja el modelo, y toda la lectura estatica
//      esta mal.
//
// Se separan al reves: forzar el salto para TODO EL MUNDO. Si desaparecen los
// bots, es (a) -- la funcion y la puerta son las correctas. Si no desaparece
// nadie, es (b) y hay que empezar de cero en otro sitio.
//
// Es la leccion de la etapa 5e literal: *"el diagnostico barato de
// match-everything valia escribirlo ANTES de la feature, no despues"*. Aqui
// costo una ronda por no hacerlo.
//
// CONTESTADO EL 2026-09-09: no desaparece nadie, ni forzando el salto ni
// anulandolo. Los dos unicos caminos de ese `jne`, y ninguno mueve un pixel:
// esa rama no dibuja modelos. Se queda por el historial, no porque sirva.

// EL CODIGO DE SITIOS VIVE EN LOS BITS 7 EN ADELANTE DEL MISMO CVar.
//
//   0            no se toca ningun sitio de llamada
//   1..18        se apaga SOLO ese (1 = kSpecCallSites[0])
//   kSitesAll    se apagan los dieciocho
//
// Un solo canal y no dos: dos CVars para una prueba es dos formas de quedarse
// a medias -- uno puesto y el otro no, sin nada que lo diga.
constexpr int32_t kSiteShift = 7;
constexpr int32_t kSiteMask  = 0x3F;   // seis bits, 0..63
constexpr int32_t kSitesAll  = 63;

// Bit 13: desarmar el arreglo automatico. Existe para poder volver a ver el
// fallo -- una cura sin forma de apagarla es una cura que no se puede volver a
// medir el dia que el sintoma cambie de sitio.
constexpr int32_t kNoFix    = 8192;
// Bit 14: apagar el parpadeo. Candidato, no cura: arranca APAGADO.
constexpr int32_t kBlinkOff = 16384;

uint8_t g_siteOrig[off::kSpecCallSiteCount][5];
uint32_t g_siteOn = 0;   // mascara de los que estan apagados AHORA MISMO
uint8_t g_blinkOrig[5];
bool g_blinkOff = false;

enum PatchState { kPatchNone = 0, kPatchNever = 1, kPatchAlways = 2 };

int g_patched = kPatchNone;
uint8_t g_originalJne[2] = {0, 0};
uint32_t g_nextReport = 0;
int32_t g_lastMode = -1;

// Direccion del dword de flags TAL Y COMO LO LEE EL PREDICADO. Deliberadamente
// no se usa el array de descriptores de siempre: si se escribiera en otro sitio
// que "tambien" tenga los flags, el predicado seguiria leyendo el suyo y la
// prueba saldria negativa por el motivo equivocado -- que es peor que no
// hacerla, porque descartaria un camino que si funciona.
bool FlagsAddress(uint32_t* out) {
    uint64_t const guid = objmgr::LocalGuid();
    if (!guid) return false;

    uint32_t addr = 0, type = 0;
    if (!objmgr::FindByGuid(guid, &addr, &type)) return false;

    uint32_t fields = 0;
    if (!mem::Deref(addr, off::kPlayer_FieldsPtr, &fields)) return false;

    *out = fields + off::kPlayerFields_Flags;
    return true;
}

// Dos bytes, un solo sitio de llamada, reversible. Es lo contrario del parche
// del 2026-09-08, que reescribio el predicado COMPARTIDO por dieciocho
// llamantes y le dijo al cliente que todo jugador era espectador.
//
// Se parchea desde el hilo principal (Publisher) y no desde el hilo de
// inyeccion, por lo mismo que Circle: el hilo que ejecuta esos bytes es este,
// asi que la escritura no puede caer a mitad de instruccion.
void SetPatch(int want) {
    if (want == g_patched) return;

    uint8_t* site = reinterpret_cast<uint8_t*>(off::kSelfSkipJne);
    DWORD prot = 0, ignored = 0;
    if (!VirtualProtect(site, sizeof(g_originalJne), PAGE_EXECUTE_READWRITE, &prot)) {
        RTS_LOG("body: VirtualProtect fallo (%lu) -- el salto NO se toca", GetLastError());
        return;
    }

    // Siempre se vuelve al original antes de escribir otra cosa: asi la firma
    // se comprueba UNA vez, contra los bytes de verdad, y no contra un parche
    // anterior nuestro.
    if (g_patched != kPatchNone) {
        memcpy(site, g_originalJne, sizeof(g_originalJne));
        g_patched = kPatchNone;
        RTS_LOG("body: salto de %08X devuelto", off::kSelfSkipJne);
    }

    if (want != kPatchNone) {
        // Se comprueba la firma antes de escribir. Un cliente distinto tiene
        // otros bytes ahi, y machacar dos bytes cualesquiera del render es la
        // forma de convertir una sonda en un cuelgue.
        if (memcmp(site, off::kSelfSkipBytes, sizeof(g_originalJne)) != 0) {
            RTS_LOG("body: en %08X hay %02X %02X y esperaba %02X %02X -- NO parcheo",
                    off::kSelfSkipJne, site[0], site[1],
                    off::kSelfSkipBytes[0], off::kSelfSkipBytes[1]);
            VirtualProtect(site, sizeof(g_originalJne), prot, &ignored);
            return;
        }
        memcpy(g_originalJne, site, sizeof(g_originalJne));

        if (want == kPatchNever) {
            site[0] = 0x90;
            site[1] = 0x90;
            RTS_LOG("body: salto de %08X anulado (jne -> nop nop) -- nadie se salta",
                    off::kSelfSkipJne);
        } else {
            // jne rel8 (0x75) -> jmp rel8 (0xEB). Mismo destino, misma
            // longitud: se salta SIEMPRE, para toda unidad.
            site[0] = 0xEB;
            RTS_LOG("body: salto de %08X FORZADO (jne -> jmp) -- se saltan TODAS",
                    off::kSelfSkipJne);
        }
        g_patched = want;
    }

    VirtualProtect(site, sizeof(g_originalJne), prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, sizeof(g_originalJne));
}

// Apaga o devuelve UN `call rel32`. Cinco bytes, y la firma se comprueba antes
// de escribir: si ahi no hay un call que apunte a `target`, no se toca nada y se
// dice que habia -- machacar cinco bytes cualesquiera del render no es una
// sonda, es un cuelgue.
bool NeuterCall(uint32_t addr, uint32_t target, uint8_t* orig, bool want,
                bool have, const char* what) {
    if (want == have) return have;

    uint8_t* site = reinterpret_cast<uint8_t*>(addr);
    DWORD prot = 0, ignored = 0;
    if (!VirtualProtect(site, 5, PAGE_EXECUTE_READWRITE, &prot)) {
        RTS_LOG("body: %s (%08X): VirtualProtect fallo (%lu)", what, addr, GetLastError());
        return have;
    }

    bool out = have;
    if (want) {
        uint32_t const dest = addr + 5 + *reinterpret_cast<int32_t*>(site + 1);
        if (site[0] != 0xE8 || dest != target) {
            RTS_LOG("body: %s (%08X): ahi no hay un call a %08X (%02X, destino %08X)"
                    " -- NO toco", what, addr, target, site[0], dest);
            VirtualProtect(site, 5, prot, &ignored);
            return have;
        }
        memcpy(orig, site, 5);
        site[0] = 0x31;  // xor eax, eax
        site[1] = 0xC0;
        site[2] = 0x90;  // nop nop nop
        site[3] = 0x90;
        site[4] = 0x90;
        out = true;
        RTS_LOG("body: %s (%08X) APAGADO -- ese llamante ve 'no'", what, addr);
    } else {
        memcpy(site, orig, 5);
        out = false;
        RTS_LOG("body: %s (%08X) devuelto", what, addr);
    }

    VirtualProtect(site, 5, prot, &ignored);
    FlushInstructionCache(GetCurrentProcess(), site, 5);
    return out;
}

void ApplySites(uint32_t want) {
    for (int i = 0; i < off::kSpecCallSiteCount; ++i) {
        char name[24];
        wsprintfA(name, "sitio %d", i);
        uint32_t const bit = 1u << i;
        bool const now = NeuterCall(off::kSpecCallSites[i], off::kIsSpectator,
                                    g_siteOrig[i], (want & bit) != 0,
                                    (g_siteOn & bit) != 0, name);
        if (now) g_siteOn |= bit; else g_siteOn &= ~bit;
    }
}

// QUE SITIOS QUEREMOS APAGADOS AHORA MISMO.
//
// Se compone de dos cosas que no se pisan: lo que pida la caminata manual, y
// EL ARREGLO, que se arma solo. Componerlas en una mascara y aplicarla entera
// evita el fallo clasico de dos dueños para el mismo byte -- que el que suelta
// el ultimo gana y el otro cree que sigue puesto.
uint32_t WantedSites(int32_t code, bool bothFlags, bool allowFix) {
    uint32_t want = 0;
    if (code == kSitesAll) {
        want = (1u << off::kSpecCallSiteCount) - 1;
    } else if (code >= 1 && code <= off::kSpecCallSiteCount) {
        want = 1u << (code - 1);
    }
    if (bothFlags && allowFix) want |= 1u << off::kSelfHideSite;
    return want;
}

}  // namespace

void Tick() {
    int32_t mode = 0;
    if (!cvar::ReadInt(kProbeCVar, &mode)) {
        // El CVar todavia no existe (el addon no ha cargado). cvar::Find ya
        // reintenta una vez por segundo, asi que aqui no hay nada que hacer --
        // pero si habia un parche puesto hay que soltarlo, porque un parche que
        // sobrevive a su interruptor es exactamente el `camHold` del 2026-08-23.
        if (g_patched) SetPatch(kPatchNone);
        if (g_siteOn) ApplySites(0);
        g_blinkOff = NeuterCall(off::kBlinkCall, off::kBlinkPredicate,
                                g_blinkOrig, false, g_blinkOff, "parpadeo");
        return;
    }

    if (mode != g_lastMode) {
        RTS_LOG("body: modo %d (flagsOn=%d flagsOff=%d skip=%d invert=%d "
                "uberOnly=%d commOnly=%d sitio=%d noFix=%d blinkOff=%d)", mode,
                (mode & kFlagsOn) ? 1 : 0, (mode & kFlagsOff) ? 1 : 0,
                (mode & kSkipPatch) ? 1 : 0, (mode & kInvert) ? 1 : 0,
                (mode & kUberOnly) ? 1 : 0, (mode & kCommOnly) ? 1 : 0,
                (mode >> kSiteShift) & kSiteMask,
                (mode & kNoFix) ? 1 : 0, (mode & kBlinkOff) ? 1 : 0);
        g_lastMode = mode;
    }

    // Forzar gana sobre anular: son opuestos, y con los dos pedidos a la vez
    // la respuesta util es la del diagnostico.
    SetPatch((mode & kInvert) != 0     ? kPatchAlways
           : (mode & kSkipPatch) != 0  ? kPatchNever
                                       : kPatchNone);

    // El parpadeo: su propio interruptor, y por defecto APAGADO -- o sea que el
    // parche NO esta puesto hasta que alguien lo pida. Sigue siendo un
    // candidato, no una cura.
    g_blinkOff = NeuterCall(off::kBlinkCall, off::kBlinkPredicate, g_blinkOrig,
                            (mode & kBlinkOff) != 0, g_blinkOff, "parpadeo");

    uint32_t addr = 0;
    if (!FlagsAddress(&addr)) {
        // Sin jugador no hay flags que mirar, asi que el arreglo automatico no
        // puede decidirse. Se deja SOLO lo que pidio la caminata manual: un
        // parche que se queda puesto porque no supimos leer es la definicion de
        // un apaño que sobrevive a su motivo.
        ApplySites(WantedSites((mode >> kSiteShift) & kSiteMask, false, false));
        return;
    }

    uint32_t flags = 0;
    if (!mem::Read<uint32_t>(addr, &flags)) {
        ApplySites(WantedSites((mode >> kSiteShift) & kSiteMask, false, false));
        return;
    }

    uint32_t const both = off::kPlayerFlagUber | off::kPlayerFlagCommentator;
    uint32_t want = flags;

    // UN BIT SOLO, QUE ES LO QUE A1 NO PODIA CONTESTAR.
    //
    // `flags on` pone los dos, asi que "los flags son la causa" no dice cual.
    // Y la diferencia decide donde se busca: el bit 19 tiene un segundo
    // consumidor conocido -- 0x00729740, el predicado de 28 llamantes que mata
    // el mouseover -- y el bit 22 solo lo mira la banda del comentarista.
    //
    // El bit contrario se BORRA, no se deja como este. Si se dejara, el heroe
    // que ya viene de un `flags on` conservaria el otro puesto y la prueba
    // mediria otra vez los dos juntos sin decirlo -- un negativo por el motivo
    // equivocado, que es peor que no medir.
    //
    // Y esto no abre la puerta del comentarista (hace falta el 19 Y, fuera de
    // arena, el 22), asi que la camara no se mueve: te miras en tercera
    // persona y ya esta.
    //
    // Apagar gana sobre encender: con varios pedidos a la vez, la respuesta
    // menos sorprendente es la que devuelve el control.
    if (mode & kFlagsOff) {
        want &= ~both;
    } else if (mode & kUberOnly) {
        want = (want | off::kPlayerFlagUber) & ~off::kPlayerFlagCommentator;
    } else if (mode & kCommOnly) {
        want = (want | off::kPlayerFlagCommentator) & ~off::kPlayerFlagUber;
    } else if (mode & kFlagsOn) {
        want |= both;
    }

    // EL ARREGLO, Y SE ARMA SOLO.
    //
    // Encontrado y confirmado en juego el 2026-09-09: con los dos flags puestos
    // el heroe desaparece, y apagar SOLO 0x006E085C lo devuelve -- tambien
    // desde la camara de comentarista, que es para lo que existia el problema.
    //
    // La condicion no es "lo hemos pedido nosotros" sino "el jugador LLEVA los
    // dos bits". Asi cubre tambien el dia que los ponga el servidor (que es
    // como los pondra la camara libre de verdad, `docs/CAMARA-LIBRE.md`), sin
    // que haya que acordarse de encender nada. Y al quitarse los flags el
    // parche se va solo, que es la regla de capturar y devolver.
    //
    // Se mira `want`, no `flags`: es lo que va a haber cuando acabe este tick.
    // Con `flags` el arreglo llegaria un tick tarde y el primer frame de la
    // camara te enseñaria invisible.
    bool const bothFlags = (want & both) == both;
    ApplySites(WantedSites((mode >> kSiteShift) & kSiteMask, bothFlags,
                           (mode & kNoFix) == 0));

    // Se reescribe CADA TICK y no una vez. El servidor puede reenviar el campo
    // en cualquier actualizacion de descriptores, y una escritura unica se
    // desharia sola sin dar ningun error -- que es el modo de fallo que esta
    // sonda existe para no volver a pagar.
    if (want != flags) mem::Write<uint32_t>(addr, want);

    if (mode & kReport) {
        uint32_t const now = GetTickCount();
        if (now >= g_nextReport) {
            g_nextReport = now + 1000;
            RTS_LOG("body: flags en %08X = %08X (uber=%d commentator=%d) parche=%d",
                    addr, want,
                    (want & off::kPlayerFlagUber) ? 1 : 0,
                    (want & off::kPlayerFlagCommentator) ? 1 : 0,
                    g_patched ? 1 : 0);
        }
    }
}

void Shutdown() {
    // Sin condicion y sin mirar el CVar. Dejar dos bytes del render puestos
    // porque "el interruptor estaba apagado" es la misma trampa que dejo los
    // flags escritos en la base de datos al deshacer la camara libre.
    if (g_patched) SetPatch(kPatchNone);
    if (g_siteOn) ApplySites(0);
    g_blinkOff = NeuterCall(off::kBlinkCall, off::kBlinkPredicate,
                            g_blinkOrig, false, g_blinkOff, "parpadeo");
}

}  // namespace selfshow

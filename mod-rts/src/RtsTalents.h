#ifndef MOD_RTS_TALENTS_H
#define MOD_RTS_TALENTS_H

#include <string>

class Player;

namespace rts
{
    // Quitar UN punto de talento, que es lo que el juego no deja hacer: en
    // 3.3.5 solo existe el reseteo entero, pagado y de golpe.
    //
    // === COMO SE QUITA: SE RESETEA Y SE VUELVE A PONER ======================
    //
    // Suena bruto y es lo contrario: es lo unico que deja las cuentas del
    // nucleo bien. Quitar el rango a mano -- `_removeTalent` y sus amigos --
    // sale facil hasta que se mira `m_usedTalentCount`, que es `protected`,
    // que no lo toca ninguna de esas funciones, y que el nucleo usa al SUBIR DE
    // NIVEL: `InitTalentForLevel` reparte los puntos libres con el, y si se
    // pasa del maximo del nivel **resetea los talentos enteros**. Un contador
    // que se queda alto por cada punto quitado es, unos niveles despues, una
    // build borrada sin que nada lo explique.
    //
    // `resetTalents(true)` lo pone a cero y `LearnTalent` lo vuelve a subir
    // solo, que son las dos unicas puertas publicas que lo escriben. Asi que:
    // se fotografia la build, se valida la build NUEVA, se resetea gratis y se
    // vuelve a aprender entera menos ese punto. El cliente recibe una sola
    // actualizacion al final y no ve el hueco.
    //
    // La validacion va ANTES del reseteo a proposito: a mitad de volver a
    // aprender no hay marcha atras, asi que lo que no se pueda reconstruir
    // tiene que descubrirse mientras todavia no se ha tocado nada.
    namespace talents
    {
        // `tab`, `tier` y `col` llegan del cliente en base 1, que es como los
        // cuenta `GetTalentInfo`. `code` sale siempre y es lo que se manda al
        // addon; `detail` lleva el nombre del talento que estorba, si hay uno.
        //
        //   OK    quitado
        //   NONE  ahi no hay ningun punto
        //   DEP   <detail> depende de el y se quedaria colgado
        //   ROW   la fila <detail> se quedaria sin los puntos que exige
        //   BAD   no existe ese talento para esta clase
        bool Remove(Player* player, uint32_t tab, uint32_t tier, uint32_t col,
                    std::string& code, std::string& detail);
    }
}

#endif  // MOD_RTS_TALENTS_H

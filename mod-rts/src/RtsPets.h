#ifndef MOD_RTS_PETS_H
#define MOD_RTS_PETS_H

#include <cstdint>

namespace rts
{
    // La felicidad de las mascotas de cazador, clavada al maximo.
    //
    // === POR QUE ===========================================================
    //
    // La felicidad es una CORREA, y en este proyecto la correa no ata a nadie:
    //
    //   * baja sola -- 670 cada 7,5 s, y x1,5 en combate (`Pet::LoseHappiness`),
    //     o sea que desde el maximo se cae a "contento" en poco mas de una hora
    //     sin hacer nada, y morir cuesta 333.000 de golpe: un tercio entero de
    //     la barra, de una vez;
    //   * y solo sube DANDOLE DE COMER, que es un hechizo del duenno. A la
    //     mascota de un bot no le da de comer nadie: el bot no sabe, y tu no
    //     puedes -- Alimentar mascota sale sobre la TUYA.
    //
    // Una mascota infeliz pega menos y acaba desobedeciendo, asi que lo que la
    // correa produce aqui no es una decision del jugador: es un impuesto que se
    // cobra solo, sobre todo a los bots, y que ademas no se ve venir.
    //
    // === POR QUE UN BARRIDO Y NO UN GANCHO =================================
    //
    // Porque no hay gancho. `PetScript` del nucleo tiene `OnInitStatsForLevel`
    // y `OnPetAddToWorld`, y ninguno de los dos es periodico: valdrian para
    // ponerla al maximo UNA vez, que es justo lo que ya se puede hacer a mano.
    // Lo que la baja es `Pet::LoseHappiness`, que vive en el nucleo -- y el
    // nucleo aqui se lee, no se edita.
    //
    // Y es barato: `Unit::SetPower` se vuelve antes de hacer nada si el valor
    // ya es el que pides, asi que un barrido por segundo no manda ni un paquete
    // mientras nada haya bajado.
    namespace pets
    {
        // Del tick del mundo. Cada `kTickMs` recorre a los jugadores conectados
        // -- los tuyos y los bots -- y le devuelve el maximo a la mascota de
        // cazador que tengan puesta.
        void Update(uint32_t diff);
    }
}

#endif  // MOD_RTS_PETS_H

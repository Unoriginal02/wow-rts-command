#ifndef MOD_RTS_TRAIN_H
#define MOD_RTS_TRAIN_H

class Player;

namespace rts
{
    // TODO LO QUE EL ENTRENADOR LE VENDERIA, DADO GRATIS.
    //
    // === ESTO NO TOCA mod-playerbots ========================================
    //
    // Ni una llamada, y esta vez es mas llamativo que de costumbre porque
    // playerbots TIENE esto escrito: `AutoMaintenanceOnLevelupAction::
    // LearnTrainerSpells` hace lo mismo. Lo que pasa es que las dos mitades que
    // lo llaman estan dentro de un
    //
    //     if (... && sRandomPlayerbotMgr.IsRandomBot(bot))
    //
    // y nuestros bots no son bots aleatorios: son alts del jugador metidos con
    // `.playerbots bot add`. Asi que a ellos no les llega nunca, y encenderlo
    // seria editar su modulo -- que aqui no se hace. Reescribirlo cuesta esta
    // pagina y se queda en nuestro lado.
    //
    // Ademas la version de playerbots pasa por `PlayerbotFactory::InitSkills`,
    // que escribe las habilidades de arma con `SetSkill` a partir de una tabla
    // de clase escrita a mano. Esta pasa por los datos del entrenador, que es
    // donde el juego dice de verdad quien puede aprender que.
    //
    // === POR QUE LOS DATOS DEL ENTRENADOR Y NO UNA LISTA NUESTRA =============
    //
    // Porque la pregunta que hay que contestar es literalmente *"que le
    // venderia su entrenador a este nivel"*, y esa respuesta ya existe montada:
    // `sObjectMgr->GetClassTrainers(clase)` mas `Trainer::CanTeachSpell`, que es
    // el mismo par que usa el comando `.learn all my trainer`
    // (`cs_learn.cpp:121`). Comprueba nivel, clase, raza, habilidad requerida,
    // hechizo previo y rango anterior.
    //
    // Lo unico que se salta es el precio: aqui no se llama a `ModifyMoney`.
    //
    // === MOD-LEARN-SPELLS NO SOBRA, PERO NO LLEGA ===========================
    //
    // El servidor ya lleva `mod-learn-spells` encendido y ese si dispara para
    // todo el mundo, bots incluidos. Lo que hace no es lo mismo: barre el
    // almacen de hechizos buscando los de la familia de la clase cuyo
    // `BaseLevel` coincide con el nivel nuevo. Es una aproximacion, y deja fuera
    // las habilidades de ARMA enteras -- son `SPELLFAMILY_GENERIC` y su filtro
    // de familia las descarta. Por eso un bot podia tener sus hechizos de clase
    // y seguir sin saber usar un arco.
    //
    // Los dos pueden convivir sin estorbarse: aprender un hechizo que ya sabes
    // no hace nada.
    namespace train
    {
        // Devuelve cuantos aprendio. Vale para un bot y para el jugador.
        int Learn(Player* who);
    }
}

#endif  // MOD_RTS_TRAIN_H

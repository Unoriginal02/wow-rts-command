// SelfShow.h -- LA SONDA DEL CUERPO. Es un instrumento, no una funcion.
//
// El heroe se vuelve invisible en cuanto su jugador lleva PLAYER_FLAGS_UBER, y
// la cadena esta desensamblada en Offsets.h: un "emite esta unidad" por unidad
// (0x0073A890) pregunta 0x006DE980 con ESE jugador y se salta la emision si
// contesta que si. Los bots no llevan los flags, asi que solo desaparece el
// tuyo -- que es el sintoma exacto -- y forzar el predicado a true escondio a
// todo el mundo, que es la otra mitad de la prueba.
//
// Esto NO arregla nada por su cuenta y NO se enciende solo. Contesta dos
// preguntas con dos interruptores independientes, en una sola sesion:
//
//   1. ¿Bastan los flags, sin modo comentarista ni servidor de por medio?
//      Se escriben en la copia del CLIENTE. Si el heroe desaparece, si.
//   2. Con los flags puestos, ¿reaparece anulando ESE salto y solo ese?
//      Si reaparece, la cura son dos bytes y no hay que tocar los 18 llamantes.
//
// Va apagado de fabrica y detras de un comando, que es la regla que costo la
// tarde del 2026-09-06 (el aro dibujado dos veces salio de serie) y la del
// 2026-09-08 (el parche de 0x006DE980 salio de serie y escondio a todos).

#pragma once
#include <cstdint>

namespace selfshow {

// Se llama una vez por tick desde Publisher, en el hilo principal.
void Tick();

// Deshace el parche de bytes si esta puesto. Se llama al descargar el DLL.
void Shutdown();

}  // namespace selfshow

// World.h -- the client's terrain/collision raycast.

#pragma once

namespace world {

struct Vec3 {
    float x, y, z;
};

// Casts a ray from `start` to `end` against terrain/WMO/M2. On a hit, returns
// true and fills `hit` (and `frac` in [0,1], the fraction along the ray).
// SEH-guarded: a bad read returns false, never crashes.
bool Raycast(const Vec3& start, const Vec3& end, Vec3* hit, float* frac);

// Igual, pero SOLO CONTRA EL TERRENO: ni edificios, ni doodads, ni nada
// colocado encima. Misma funcion del cliente con otra mascara de banderas --
// la evidencia de por que 0x100 apaga la mitad de objetos esta en `Offsets.h`,
// junto a `kIntersectFlagsTerrain`.
//
// Existe porque "lo primero que hay debajo" y "el suelo" no son lo mismo en
// cuanto hay una casa: la camara libre necesita el segundo.
bool RaycastTerrain(const Vec3& start, const Vec3& end, Vec3* hit, float* frac);

}  // namespace world

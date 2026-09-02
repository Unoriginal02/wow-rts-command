/*
 * RtsMarks.h -- ground markers for route waypoints, drawn by the CLIENT.
 *
 * Everything the RTS layer has drawn "in the world" until now was either a UI
 * texture the addon parks at a projected pixel -- no depth, swims when the
 * camera turns -- or one of the client's own per-UNIT effects (the selection
 * circle, the model glow, the nameplate), all of which need a GUID to hang on.
 * A route waypoint is bare ground with nothing there to hang anything on.
 *
 * A DynamicObject is the exception: it lives at an arbitrary world position and
 * the client renders its spell's persistent-area visual there, in its own
 * pipeline, with correct depth. That is what a Consecration or a Death and
 * Decay patch is. So the marker is not drawn by us at all -- we place an object
 * and the client draws it, which is the same trade that made the nameplates
 * work in stage 5e.
 *
 * WHICH SPELL is the open question, and it is a question for the eye, not for
 * the code: every visual has its own size, colour and animation. So the look is
 * server-side state with a step-through tool (MARKSET next/prev/find), and the
 * candidate list is BUILT FROM THE LOADED SPELL STORE -- every spell with a
 * persistent-area-aura effect, which is exactly the set the client has a ground
 * visual for. Nothing here is a spell id written from memory; see
 * `Candidates()`.
 */

#ifndef MOD_RTS_MARKS_H
#define MOD_RTS_MARKS_H

#include "Position.h"

#include <cstdint>
#include <string>
#include <vector>

class Player;

namespace rts
{
    namespace marks
    {
        // The per-player look. Owned here while the player is online; the addon
        // keeps its own copy in SavedVariables and re-sends it on login, so a
        // chosen visual survives a logout without this module storing anything.
        // 45848 "Shield of the Blue", chosen by eye in game out of the 572
        // candidates. Hardcoded as the DEFAULT, not as a constant: the
        // step-through tool still works, this is just where it starts.
        constexpr uint32 kDefaultSpell = 45848;

        // A tenth of the spell's own radius, which is what looked right in game.
        // Expressed as a FRACTION and not as yards because the yard figure means
        // nothing on its own -- it only makes sense next to the size the visual
        // was drawn at, and that differs per spell.
        constexpr float kDefaultScale = 0.1f;

        // A SECOND SIZE LEVER, because the first one is not ours to enforce.
        // DYNAMICOBJECT_RADIUS is a request: the client decides whether a given
        // ground visual scales with it at all, and for a visual that does not,
        // every size we send is stored, echoed back and ignored -- which reads
        // as "the knob is broken" and is not. OBJECT_FIELD_SCALE_X is a
        // different field on a different path (the model's own scale, the same
        // one that makes a creature big or small), so a visual deaf to one may
        // answer the other. Which one a given visual listens to is a thing to
        // look at, not to reason about -- same call as the mode above.
        constexpr float kDefaultObjScale = 1.0f;

        struct Look
        {
            uint32 spell = kDefaultSpell;
            float radius = 0.0f;   // 0 = automatic: kDefaultScale x the spell's own
            float obj = kDefaultObjScale;   // OBJECT_FIELD_SCALE_X
            uint8 mode = 0;        // DynamicObjectType: 0 portal, 1 area spell
            std::size_t index = 0; // position in the candidate list
        };

        struct Cand
        {
            uint32 id;
            std::string name;
        };

        // Spells with a persistent-area-aura effect, sorted by id. Built once,
        // from sSpellMgr, on first use.
        std::vector<Cand> const& Candidates();

        // Current look, and the knobs that change it. Every setter re-places
        // the player's existing markers, so stepping through visuals shows the
        // change on the route already on the ground.
        Look const& Get(Player* player);
        void SetSpell(Player* player, uint32 spellId);
        void SetRadius(Player* player, float radius);   // <= 0 = back to automatic
        void SetScale(Player* player, float scale);     // radius = scale x the spell's own
        void SetObjScale(Player* player, float scale);  // OBJECT_FIELD_SCALE_X

        // The radius the spell itself was designed with, straight out of its
        // effect data. This is the "original" that a scale is a fraction OF.
        float SpellRadius(uint32 spellId);

        // What actually goes on the wire for the current look.
        float EffectiveRadius(Look const& look);
        void SetMode(Player* player, uint8 mode);
        void Step(Player* player, int delta);
        bool Find(Player* player, std::string const& text);

        // Name of the current spell, or "?" when it is not in the store.
        std::string NameOf(uint32 spellId);

        // slot is the waypoint number. Placing over an occupied slot replaces
        // it; slot 0 in Remove means all of them.
        bool Place(Player* player, uint32 slot, Position const& pos);
        void Remove(Player* player, uint32 slot);
        void RemoveAll(Player* player);
        std::size_t Count(Player* player);

        // Logout: drop our bookkeeping. The objects themselves are already
        // taken down by the core (Unit::CleanupBeforeRemoveFromMap), and the
        // same is true of a map change (Player::TeleportTo) -- which matters,
        // because DynamicObject::Update ASSERTs that its caster is on the same
        // map and would otherwise take the server down with us.
        void ForgetPlayer(Player* player);
    }
}

#endif

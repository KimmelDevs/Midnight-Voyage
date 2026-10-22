# Midnight Voyage — Roadmap notes

## Done
- Café, food star tiers, gacha, 5 café jobs, night build mode, auto-battles.
- **Sky Café airship**: the café map is the ship deck, built tile by tile from
  `GS.ship` (deck mask, cabin, gangway) using the ChatGPT ship kit
  (`art_src/mv_ship_kit.png` → `tools/cut_ship_kit.py` → `assets/ship/`).

## Next: airship systems (ship first, islands later)
From the "Airship Management System — Design Plan v1":
- Skyheart Core engine, Aether fuel (only used when travelling; basic fuel always buyable at docks).
- Ship stats: Hull HP, Engine Power, Fuel Efficiency/Capacity, Cargo Capacity, Stability, Crew/Café Capacity.
- Ship crew roles from the same five stats (Captain HOS+FOC, Pilot AGI+FOC, Navigator FOC+TEC,
  Engineer TEC+END, Quartermaster FOC+END, Purser HOS+FOC, Lookout FOC+AGI, Deckhand END+AGI).
  Station performance = 0.65·P + 0.35·S + 1.5·Mastery + Trait, capped bonuses.
  Separate saved assignments per activity (café shift / travel shift / battle party).
- Shared categorised storage: dry pantry, refrigerator, cargo hold, fuel tank, equipment locker,
  display storage; stack limits, weight, freshness; overflow goes to a delivery queue, never deleted.
- Maintenance: hull condition, engine condition, crew meals as travel buffs.
- Ship upgrades map to rooms/furniture; big structures (engine) span multiple tiles.
- **Ship expansion**: buy deck tiles; hull, railings and walls re-assemble from the deck mask.

## Later: islands
- Starting island / town (Town Hall caps facilities; Shop, Tavern, Guild, Blacksmith, Farm, Alchemy).
  Building art already generated: `art_src/mv_buildings.png`.
- Destinations: Meadowport, Berryhaven, Moonmarket, Ironhaven, Royal Aerie; fuel vs. profit decisions.
- **Trade goods (non-ingredient items)**: goblin wares, daggers and other goods that crew can be
  ordered to sell to shops outside the ship. Build only once islands exist.
- Travel encounters reuse the existing auto-battler.

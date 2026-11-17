# Police Chase VR (Meta Quest 3)

An open-city VR sandbox for Meta Quest 3, built with Godot 4.5 and OpenXR.
The police chase you, you steal cars, and you fight with fists, melee weapons, guns, and superpowers.
It is gory: blood sprays and pools, limbs come off, heads pop, and bodies come apart.

**APK:** [`build/PoliceChaseVR.apk`](build/PoliceChaseVR.apk) (arm64, about 95 MB)

## Install on the Quest 3

1. Turn on developer mode for the headset in the Meta Horizon phone app (Devices → Developer Mode).
2. Connect the headset to a computer with USB-C and accept the "Allow USB debugging" prompt inside the headset.
3. Install the APK with SideQuest (drag the APK onto it) or with adb:

   ```
   adb install -r build/PoliceChaseVR.apk
   ```

4. In the headset, open the app library, choose **Unknown Sources**, and launch **Police Chase VR**.

Play standing or room-scale with some free space, because you will swing your arms hard.

## Controls

| Input | Action |
| --- | --- |
| Left stick | Walk (head-relative) |
| Right stick | Snap turn 40° |
| Swing an empty fist | Punch with super strength. Fast swings launch people and dent cars. |
| Grip | Grab whatever your hand touches: weapons, people, ragdolls, props, even cars. Release while swinging to throw. |
| Trigger, empty hand | **Telekinesis.** Grabs the person, car or object you point at. Stick up/down pushes it away or pulls it in. Grip yanks it into your hand. Flick your hand and let go of the trigger to hurl it. |
| Trigger, holding a gun | Shoot (pistol, shotgun, SMG) |
| Stick click | **Force push** shockwave in the direction your hand points |
| A | Super jump |
| B | Steal the nearest car (the driver gets thrown out) or get out |
| X | **Bullet time** for 4 seconds, 12 second cooldown. You keep moving at full speed. |
| Y | Recenter |
| In a car | **Steer with the steering wheel:** reach out, grab the rim with grip and turn it, with one hand or both. Right trigger is gas, left trigger is brake and reverse, A is the horn, left stick click is the handbrake, B gets out and Y re-seats you. You can drive one-handed and shoot out of the window with the other. |

Your left wrist shows health, wanted stars, what each hand holds, score and the bullet-time cooldown.

## Gameplay

- **Wanted level, 0 to 5 stars.** It rises when you hit people, kill, steal cars or attack police. Police on foot chase you with batons and then pistols. Police cars hunt you with sirens, ram you, and drop off officers. The level fades if no cop sees you for about 18 seconds.
- **Weapons.** There is a bat, baton, knife, machete, axe, pistol, shotgun and SMG. Several lie around the spawn point, more appear over time, and dead cops drop theirs. Edged weapons cut limbs off. Blunt hits and shotgun blasts to the head pop it.
- **People are physics ragdolls.** You can grab them by hand, carry them, throw them into walls or cars, or hold them in mid-air with telekinesis. Hard impacts hurt them. If they survive, they get back up and run.
- **Cars.** You can run people over, launch cars with telekinesis or force push, and blow them up. Wrecked cars burn and catch nearby people in the blast.
- If you die, you respawn nearby with your wanted level cleared.

## Graphics

- **People** are smooth, sculpted bodies on an 11-bone skeleton: faces with eyes, brows, nose, lips and ears, hair styles, beards, sunglasses, hands with fingers, shoes, and clothing that varies (t-shirts or long sleeves, jeans or shorts, belts, prints). Police wear a uniform, cap, badge, duty belt and holster. They walk, run, flee, look at you, aim and swing with bending knees and elbows.
- **Ragdolls** use the same 11 bones, so bodies fold at the knees and elbows. Any joint can be severed (head, shoulders, elbows, hips, knees, or the waist to cut someone in half), with flesh and bone stumps, dripping blood, wounds where they were hit, and blood pools that spread under the body.
- **Cars** are lofted bodies with wheel arches, raked windshields, pillars, side windows, door seams, mirrors, headlights, grilles, bumpers, plates and spoked rims. There are sedans, hatchbacks, SUVs, vans, taxis and black-and-white police cruisers with a push bar and light bar. Each has a cabin interior with seats and dashboard, and real seated drivers. Crashes, punches and thrown objects leave visible dents.
- **The city** uses CC0 photo textures: asphalt with lane markings, crosswalks, stop lines and manholes; raised concrete sidewalks with curbs; brick, stone and glass facades on the buildings, with shopfronts, signs and lit shop interiors on the ground floor. There are trees, street lamps, traffic lights, hydrants, bins and benches. A ring of towers forms the skyline. The sun casts real-time shadows near the player.
- **Driving** uses the real steering wheel in front of you: your hands snap onto the rim, it turns up to 150° each way, it centres itself when you let go, and you feel the road, skids and crashes through the controllers. The engine revs through a six-speed gearbox, tyres squeal when you slide, and you hear the doors and ignition when you get in.
- **Sound** uses real recordings (all CC0, see `CREDITS.md`): studio-recorded pistols, shotguns and submachine guns with separate far-away versions, an urban echo on gunfire, punches, wet impacts, bone breaks, bodies hitting the ground, male and female screams, pain and death cries, metal and glass crashes, a real siren and car horn, footsteps, and a constant traffic and wind ambience. Everything plays through a light reverb and a limiter.
- **Impacts** react to what they hit: dust and a bullet hole on concrete, sparks and a dent on cars, shattering glass on car windows, and the odd ricochet. Guns recoil and eject casings that tinkle on the ground.
- **Blood** builds up on your hands as you punch people and handle bodies, and splatters onto cars that run people over. Trees sway in the wind.
- **Hands** sit where your real hands are. They follow the controller's OpenXR grip pose (the palm around the handle), with the handle running diagonally across the palm like a real fist, while guns, telekinesis and force push use the controller's aim ray. Each hand has a shaped palm, three-jointed fingers with knuckles and fingernails, a thumb with its muscle mound, and a jacket sleeve. The fingers follow the Touch controllers: the index finger follows the trigger and lifts to point when you take it off, the other three follow the grip, and the thumb rests or lifts depending on whether it touches the stick or buttons. Melee weapons are held by the handle with the blade edge forward, and guns line up with where you point. The status display sits on the back of your left wrist like a watch.

## Built for a steady 90 fps

- Uses Godot's Compatibility (OpenGL ES 3) renderer, which is the renderer Godot recommends for Quest. It requests 90 Hz and matches the physics rate to it.
- 4x MSAA and high dynamic foveated rendering. Shadows use one 2048 cascade that only covers the 28 m around you, and soft blob shadows cover the rest.
- All buildings are one MultiMesh using a texture array of facades. Roads are one shaded plane and sidewalks one mesh. Street furniture is grouped into 2×2-block chunks so only nearby chunks are drawn.
- Each person is one skinned mesh (one draw call) with two levels of detail: about 5,000 triangles within 14 m and about 2,300 beyond. A car body is about 4,300 triangles; its interior only draws within 14 m.
- All people looks, car bodies and weapons are generated once at startup (about 1 second on a PC), so nothing is built during play.
- A busy street renders in about 200 draw calls and 650,000 triangles including the shadow pass, measured on desktop. It has not been profiled on a headset yet.
- Blood decals are one MultiMesh ring buffer and blood particles are pooled. Ragdolls freeze when they come to rest, and the number of live ragdolls is capped.
- People, cars and props spawn around the player and despawn behind them. Small details are culled with distance.
- All sound is synthesized at startup, so the APK has no audio files.

## Project layout

| Path | What it is |
| --- | --- |
| `scripts/main.gd` | Startup, OpenXR setup, spawning and despawning, a headless self-test and a screenshot mode |
| `scripts/player.gd`, `scripts/hand.gd` | VR body, locomotion, driving, punching, grabbing, telekinesis and force push |
| `scripts/body_gen.gd`, `scripts/ped.gd`, `scripts/ragdoll.gd` | Human bodies and looks, civilian and police AI and animation, ragdolls, dismemberment and gibbing |
| `scripts/car_gen.gd`, `scripts/car.gd` | Car bodies and interiors, driving, traffic and police pursuit AI, carjacking, dents, crashes and explosions |
| `scripts/geo.gd` | The procedural modelling toolkit: lofts, lathes, rounded boxes, capsules, skinning |
| `shaders/`, `textures/` | Road, sidewalk and building shaders and the CC0 textures (see `CREDITS.md`) |
| `scripts/weapon.gd` | Melee and gun logic |
| `scripts/city.gd` | Procedural city, shaders, lighting and road and sidewalk navigation |
| `scripts/gore.gd`, `scripts/sfx.gd`, `scripts/hud.gd` | Blood effects, procedural audio and the wrist HUD |
| `addons/godotopenxrvendors` | Godot OpenXR Vendors plugin 4.2.0, which provides the Meta OpenXR loader |

## Building the APK yourself

On Linux x86_64:

```
tools/build_apk.sh
```

The script downloads Godot 4.5.2, the export templates, JDK 17 and the Android SDK and NDK the first time it runs, about 3 GB in total. It then exports `build/PoliceChaseVR.apk`.
Signing keys are generated into `keys/`, which is not committed.
An APK signed with a new key cannot install over one signed with a different key, so uninstall the old app first.

To open the project in the Godot 4.5 editor, use **Project → Install Android Build Template**, then **Project → Export → Meta Quest**.

Headless checks:

```
godot --headless --path . -- --autotest              # exercises combat, powers, driving, explosions, death
godot --headless --path . -- --soak                  # 40 s unattended chase with a high wanted level
godot --headless --path . -- --drivetest             # prints speed, gear, revs and turn rate while driving
godot --path . -- --screenshot=/tmp/shot.png         # renders review screenshots (needs a display)
godot --path . res://tools/viewer.tscn -- --what=people --shot=/tmp/p.png   # model viewer: people, faces, cars, weapons, hands
```

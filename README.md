# Police Chase VR (Meta Quest 3)

An open-city VR sandbox for Meta Quest 3, built with Godot 4.5 and OpenXR.
The police chase you, you steal cars, and you fight with fists, melee weapons, guns, and superpowers.
It is gory: blood sprays and pools, limbs come off, heads pop, and bodies come apart.

**APK:** [`build/PoliceChaseVR.apk`](build/PoliceChaseVR.apk) (arm64, about 78 MB)

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
| In a car | Right trigger is gas, left trigger is brake and reverse, left stick steers, right grip brakes hard. You can shoot out of the window with a gun in your left hand. |

Your left wrist shows health, wanted stars, what each hand holds, score and the bullet-time cooldown.

## Gameplay

- **Wanted level, 0 to 5 stars.** It rises when you hit people, kill, steal cars or attack police. Police on foot chase you with batons and then pistols. Police cars hunt you with sirens, ram you, and drop off officers. The level fades if no cop sees you for about 18 seconds.
- **Weapons.** There is a bat, baton, knife, machete, axe, pistol, shotgun and SMG. Several lie around the spawn point, more appear over time, and dead cops drop theirs. Edged weapons cut limbs off. Blunt hits and shotgun blasts to the head pop it.
- **People are physics ragdolls.** You can grab them by hand, carry them, throw them into walls or cars, or hold them in mid-air with telekinesis. Hard impacts hurt them. If they survive, they get back up and run.
- **Cars.** You can run people over, launch cars with telekinesis or force push, and blow them up. Wrecked cars burn and catch nearby people in the blast.
- If you die, you respawn nearby with your wanted level cleared.

## Built for a steady 90 fps

- Uses Godot's Compatibility (OpenGL ES 3) renderer, which is the renderer Godot recommends for Quest. It requests 90 Hz and matches the physics rate to it.
- 4x MSAA, high dynamic foveated rendering, and no real-time shadows. Soft blob shadows are used instead.
- The city is procedural and drawn with very few calls. All buildings are one MultiMesh with a procedural window shader. Trees, lamps and their shadows are MultiMeshes too. The roads are one shader on one plane.
- People, cars and weapons are merged into single meshes from pooled looks, drawn with one shared vertex-colour shader. A person costs 6 draw calls and a car about 10. A busy street view renders in about 200 draw calls.
- Blood decals are one MultiMesh ring buffer and blood particles are pooled. Ragdolls freeze when they come to rest, and the number of live ragdolls is capped.
- People, cars and props spawn around the player and despawn behind them. Small details are culled with distance.
- All sound is synthesized at startup, so the APK has no audio files.

## Project layout

| Path | What it is |
| --- | --- |
| `scripts/main.gd` | Startup, OpenXR setup, spawning and despawning, a headless self-test and a screenshot mode |
| `scripts/player.gd`, `scripts/hand.gd` | VR body, locomotion, driving, punching, grabbing, telekinesis and force push |
| `scripts/ped.gd`, `scripts/ragdoll.gd` | Civilians and police AI, ragdolls, dismemberment and gibbing |
| `scripts/car.gd` | Drivable cars, traffic and police pursuit AI, carjacking, crashes and explosions |
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
godot --path . -- --screenshot=/tmp/shot.png         # renders review screenshots (needs a display)
```

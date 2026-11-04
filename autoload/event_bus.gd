extends Node
## Cross-system event hub, autoloaded as `EventBus`.
##
## "Call down, signal up": a parent drives its children with direct calls, while
## anything that needs to tell the rest of the game about a fact emits a signal
## here. Subscribe with `EventBus.player_died.connect(_on_player_died)`.
##
## Every signal is typed. When a new cross-system event is needed, add the signal
## here rather than inventing a second bus.

# --- Player -----------------------------------------------------------------

## Emitted when the player runs out of health and the death flow should start.
signal player_died

## Emitted once the player has been restored at a checkpoint and gameplay resumes.
signal player_respawned

## Emitted when the player's health or stamina changes, for HUD consumers.
## `current` and `maximum` are in the component's own units.
signal player_health_changed(current: float, maximum: float)
signal player_stamina_changed(current: float, maximum: float)

## Emitted when the player mounts or dismounts the cat.
signal mount_mounted
signal mount_dismounted

## Emitted when the mount's own health changes, for the small HUD bar.
signal mount_health_changed(current: float, maximum: float)

# --- Combat -----------------------------------------------------------------

## Emitted by a hurtbox when it takes damage. `amount` is post-mitigation.
signal damage_dealt(target: Node, amount: float, is_weak_point: bool)

## Emitted when an actor's poise breaks and the riposte window opens.
signal poise_broken(actor: Node)

## Emitted when lock-on acquires, switches or releases its target.
## `target` is null when lock-on releases.
signal lock_on_changed(target: Node)

# --- Boss and level flow ----------------------------------------------------

## Emitted when the player enters the boss arena gate.
signal boss_engaged(boss: Node)

## Emitted when the boss's phase changes (1-based).
signal boss_phase_changed(boss: Node, phase: int)

## Emitted when the boss dies and the arena should open again.
signal boss_defeated(boss: Node)

## Emitted when the player rests at a Mushroom Ring checkpoint.
signal checkpoint_rested(checkpoint: Node)

# --- Game flow --------------------------------------------------------------

## Emitted when an interactable enters or leaves the player's interaction range.
## `interactable` is null when nothing is in range.
signal interaction_target_changed(interactable: Node)

## Emitted when the run is won, for the victory screen.
signal game_won

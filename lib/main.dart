// ═══════════════════════════════════════════════════════════════════════════
// ASTEROIDS GAME - Classic arcade shooter built with Flutter Flame Engine
// ═══════════════════════════════════════════════════════════════════════════
// This is a faithful recreation of the classic Atari Asteroids game featuring:
// - Vector-style graphics
// - Progressive difficulty (more asteroids each level)
// - Asteroid splitting mechanics
// - Explosion effects with screen freeze
// - Sound effects
// - Lives system with invincibility frames
// ═══════════════════════════════════════════════════════════════════════════

// Core Dart library for mathematical operations (trigonometry, random numbers)
import 'dart:math' as math;

// Flame engine imports for game development
import 'package:flame/collisions.dart';    // Collision detection system
import 'package:flame/components.dart';    // Game components (sprites, shapes, etc.)
import 'package:flame/game.dart';          // Core game loop and engine
import 'package:flame/input.dart';         // Keyboard/touch input handling
import 'package:flame/text.dart';          // Text rendering components
import 'package:flame_audio/flame_audio.dart'; // Audio playback system

// Flutter framework imports
import 'package:flutter/material.dart';    // UI widgets and material design
import 'package:flutter/services.dart';    // Keyboard key constants

/// Application entry point - initializes and launches the game
void main() {
  runApp(const GameApp());
}

/// Root widget of the application
///
/// This is a stateless widget that sets up the Flutter MaterialApp and
/// integrates the Flame game engine. It creates a fullscreen black canvas
/// for the game to render on.
class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asteroids Game',
      debugShowCheckedModeBanner: false, // Remove debug banner for cleaner look
      home: Scaffold(
        backgroundColor: Colors.black, // Classic arcade black background
        body: GameWidget(
          game: AsteroidsGame(), // Our main game instance
          focusNode: FocusNode(), // Ensures keyboard input is captured properly
          autofocus: true,        // Automatically focus on game start
        ),
      ),
    );
  }
}

/// Simple sound effects manager for game audio
///
/// This class uses static methods to provide centralized audio management.
/// All sounds are preloaded during initialization for instant playback.
///
/// Required audio files (place in assets/audio/ directory):
///   - laser.wav: Played when ship fires bullets
///   - asteroid_hit.wav: Played when bullet destroys asteroid
///   - ship_explosion.wav: Played when ship collides with asteroid
///
/// Note: Make sure to declare these in pubspec.yaml under assets
class Sfx {
  /// Preloads all sound effects into memory
  ///
  /// This should be called during game initialization (in onLoad)
  /// to avoid playback delays during gameplay.
  static Future<void> init() async {
    await FlameAudio.audioCache.loadAll([
      'laser.wav',
      'asteroid_hit.wav',
      'ship_explosion.wav',
    ]);
  }

  /// Plays the laser firing sound (spacebar pressed)
  static void fire() {
    FlameAudio.play('laser.wav');
  }

  /// Plays the asteroid destruction sound (bullet hits asteroid)
  static void asteroidHit() {
    FlameAudio.play('asteroid_hit.wav');
  }

  /// Plays the ship explosion sound (ship hits asteroid)
  static void shipExplosion() {
    FlameAudio.play('ship_explosion.wav');
  }
}

/// Main game class that manages the entire Asteroids game
///
/// This extends FlameGame and includes:
/// - HasKeyboardHandlerComponents: Allows keyboard input handling
/// - HasCollisionDetection: Enables collision detection between game objects
///
/// Game Flow:
/// 1. Game starts with ship in center and level 1 asteroids
/// 2. Player shoots asteroids which split into smaller pieces
/// 3. Level advances when all asteroids destroyed
/// 4. Ship respawns with invincibility after collision
/// 5. Game over when all lives lost
class AsteroidsGame extends FlameGame
    with HasKeyboardHandlerComponents, HasCollisionDetection {
  
  // ═══════════════════════════════════════════════════════════════════════
  // GAME STATE VARIABLES
  // ═══════════════════════════════════════════════════════════════════════
  
  /// Reference to the player's ship (nullable for respawn scenarios)
  Spaceship? ship;
  
  /// Random number generator for asteroid spawning and velocities
  final math.Random _rand = math.Random();

  /// Flag indicating if game has ended (no more lives)
  bool isGameOver = false;
  
  /// Current game level - determines number of asteroids to spawn
  /// Level 1 = 1 asteroid, Level 2 = 2 asteroids, etc.
  int level = 1;
  
  /// Tracks how many asteroids currently exist in the game
  /// When this reaches 0, we advance to the next level
  int asteroidCount = 0;

  /// Number of extra lives remaining (ships shown in upper-left dock)
  /// Player starts with 3 extra lives + the current ship = 4 total lives
  int extraLives = 3;

  /// Freezes all game object movement during explosion animations
  /// This creates a dramatic pause effect when ship is destroyed
  bool freezeForExplosion = false;

  /// Convenience getter to check if game is active (not game over)
  bool get isPlaying => !isGameOver;

  /// Sets the background color to black for classic arcade feel
  @override
  Color backgroundColor() => Colors.black;

  // ═══════════════════════════════════════════════════════════════════════
  // GAME LIFECYCLE METHODS
  // ═══════════════════════════════════════════════════════════════════════

  /// Initializes the game when it first loads
  ///
  /// This is called once at startup and sets up:
  /// 1. Sound effects (preloads all audio files)
  /// 2. Starfield background (200 stars for visual depth)
  /// 3. Lives indicator (shows remaining ships in upper-left)
  /// 4. Player's spaceship (centered on screen)
  /// 5. Initial level (spawns asteroids in a ring formation)
  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Load and cache all sound effects for instant playback
    await Sfx.init();

    // Add background starfield (renders behind everything with priority -10)
    add(Starfield());
    
    // Add lives display in upper-left corner
    add(LivesDock());

    // Create and add the player's ship at screen center
    ship = Spaceship();
    add(ship!);

    // Begin level 1 (spawns initial asteroids)
    startLevel();
  }

  /// Handles window/screen resize events
  ///
  /// When the game window is resized, this ensures the ship stays centered.
  /// This is important for responsive design and window management.
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Reposition ship to center if it exists and is active
    if (ship != null && ship!.parent != null) {
      ship!.position = size / 2;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GAME OBJECT SPAWNING
  // ═══════════════════════════════════════════════════════════════════════

  /// Creates and spawns a bullet from the ship
  ///
  /// This is called when the player presses spacebar. Bullets:
  /// - Travel in a straight line at the ship's current angle
  /// - Move at 400 pixels/second
  /// - Are removed when they leave the screen
  /// - Destroy asteroids on collision
  ///
  /// [position] Starting position (typically ship's nose)
  /// [angle] Direction to fire (in radians, ship's rotation)
  void spawnBullet(Vector2 position, double angle) {
    // Don't spawn bullets if game is over or during explosion freeze
    if (!isPlaying || freezeForExplosion) return;

    // Create bullet with specified angle and properties
    final bullet = Bullet(angle: angle)
      ..position = position      // Start at ship's position
      ..anchor = Anchor.center;  // Center anchor for collision detection

    // Add bullet to game world
    add(bullet);

    // Play laser sound effect for audio feedback
    Sfx.fire();
  }

  /// Creates and spawns an asteroid in the game world
  ///
  /// Asteroids have three size levels:
  /// - Level 2 (Large): 60px diameter - spawned at level start
  /// - Level 1 (Medium): 40px diameter - split from large asteroids
  /// - Level 0 (Small): 24px diameter - split from medium asteroids
  ///
  /// When destroyed, asteroids split into 2 smaller asteroids (if not smallest).
  ///
  /// [sizeLevel] Size tier (2=large, 1=medium, 0=small)
  /// [position] Spawn location (random if not specified)
  /// [velocity] Movement speed and direction (random if not specified)
  void spawnAsteroid({
    required int sizeLevel,
    Vector2? position,
    Vector2? velocity,
  }) {
    // Generate random velocity if not provided
    // Range: -60 to +60 pixels/second in both X and Y
    final vel = velocity ??
        Vector2(
          (_rand.nextDouble() - 0.5) * 120,  // Random X velocity
          (_rand.nextDouble() - 0.5) * 120,  // Random Y velocity
        );

    // Create asteroid with specified properties
    final asteroid = Asteroid(
      sizeLevel: sizeLevel,
      velocity: vel,
    )
      // Set position (random within screen bounds if not specified)
      ..position = position ??
          Vector2(
            _rand.nextDouble() * size.x,  // Random X position
            _rand.nextDouble() * size.y,  // Random Y position
          )
      ..anchor = Anchor.center;  // Center anchor for rotation and collision

    // Increment counter to track when all asteroids are destroyed
    asteroidCount++;
    
    // Add asteroid to game world
    add(asteroid);
  }

  /// Splits a destroyed asteroid into two smaller asteroids
  ///
  /// This is the core mechanic of Asteroids - when you destroy a large/medium
  /// asteroid, it breaks into 2 smaller pieces that fly apart. This creates
  /// an escalating challenge as one asteroid becomes many.
  ///
  /// Splitting behavior:
  /// - Large (2) → Two Medium (1) asteroids
  /// - Medium (1) → Two Small (0) asteroids
  /// - Small (0) → Destroyed completely (no split)
  ///
  /// [parent] The asteroid that was just destroyed
  void splitAsteroid(Asteroid parent) {
    // Calculate the size level for child asteroids
    final newLevel = parent.sizeLevel - 1;
    
    // If we're at the smallest size, don't split (just destroy)
    if (newLevel < 0) return;

    // Create 2 smaller asteroids from the parent
    for (var i = 0; i < 2; i++) {
      // Random angle for the split trajectory (0 to 2π radians)
      final angle = _rand.nextDouble() * math.pi * 2;
      
      // Random speed (80-140 pixels/second)
      final speed = 80 + _rand.nextDouble() * 60;
      
      // Calculate velocity vector from angle and speed
      // cos(angle) gives X component, sin(angle) gives Y component
      final vel = Vector2(math.cos(angle), math.sin(angle)) * speed;

      // Spawn the child asteroid at parent's location with new velocity
      spawnAsteroid(
        sizeLevel: newLevel,
        position: parent.position.clone(),  // Same position as parent
        velocity: vel,                       // Unique random direction
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LEVEL MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Called when an asteroid is removed from the game
  ///
  /// This is automatically triggered by the Asteroid's onRemove() method.
  /// It decrements the asteroid counter and checks if the level is complete.
  ///
  /// Level completion occurs when asteroidCount reaches 0, meaning all
  /// asteroids (including split pieces) have been destroyed.
  void onAsteroidDestroyed() {
    // Don't process if game is over
    if (!isPlaying) return;

    // Decrease the count of active asteroids
    asteroidCount--;

    // If all asteroids destroyed, advance to next level
    if (asteroidCount <= 0) {
      nextLevel();
    }
  }

  /// Spawns asteroids for the current level
  ///
  /// Creates a visually pleasing ring formation of asteroids around the
  /// screen center. The number of asteroids equals the current level number.
  ///
  /// Formation strategy:
  /// - Asteroids are positioned in a circle around screen center
  /// - Each asteroid moves tangentially (perpendicular to radius)
  /// - This creates a rotating pattern that spreads out
  /// - Ring radius is 35% of screen size (clamped 80-400px)
  ///
  /// Difficulty scaling:
  /// - Level 1: 1 asteroid
  /// - Level 2: 2 asteroids
  /// - Level 10: 10 asteroids (gets challenging!)
  void startLevel() {
    // Calculate screen center point
    final center = size / 2;
    
    // Calculate ring radius for asteroid spawning
    // Use 35% of smaller screen dimension, but keep between 80-400px
    final double ringRadius =
        (math.min(size.x, size.y) * 0.35).clamp(80.0, 400.0).toDouble();

    // Spawn asteroids evenly distributed around the ring
    for (var i = 0; i < level; i++) {
      // Calculate angle for this asteroid's position
      // Distributes evenly: 0°, 120°, 240° for 3 asteroids, etc.
      final angle = (2 * math.pi * i) / level;

      // Convert angle to direction vector (unit circle)
      final dir = Vector2(math.cos(angle), math.sin(angle));
      
      // Calculate spawn position along the ring
      final pos = center + dir * ringRadius;

      // Calculate tangent angle (perpendicular to radius)
      // Adding π/2 rotates the vector 90 degrees
      final tangentAngle = angle + math.pi / 2;
      
      // Random speed between 60-140 pixels/second
      final speed = 60 + _rand.nextDouble() * 80;
      
      // Calculate velocity in tangent direction
      final vel =
          Vector2(math.cos(tangentAngle), math.sin(tangentAngle)) * speed;

      // Spawn a large (level 2) asteroid at this position
      spawnAsteroid(
        sizeLevel: 2,      // Always start with large asteroids
        position: pos,     // Position on the ring
        velocity: vel,     // Tangential movement
      );
    }
  }

  /// Advances to the next level
  ///
  /// Called when all asteroids have been cleared. This method:
  /// 1. Increments the level number (infinite progression)
  /// 2. Resets the ship's position and velocity
  /// 3. Spawns new asteroids for the next level
  ///
  /// Note: Levels continue indefinitely - each level adds one more asteroid
  void nextLevel() {
    // Increment level counter (no maximum - keeps getting harder!)
    level++;

    // Reset ship to center if it exists and is in the game
    if (ship != null && ship!.parent != null) {
      ship!
        ..position = size / 2        // Center of screen
        ..velocity = Vector2.zero()  // Stop all movement
        ..angle = 0;                 // Reset rotation to pointing up
    }

    // Spawn asteroids for the new level
    startLevel();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // COLLISION & RESPAWN HANDLING
  // ═══════════════════════════════════════════════════════════════════════

  /// Handles the collision between ship and asteroid with cinematic effect
  ///
  /// This creates a dramatic death sequence:
  /// 1. Plays explosion sound
  /// 2. Freezes all game objects (bullets, asteroids, ship)
  /// 3. Spawns dual explosion effects (white for ship, grey for asteroid)
  /// 4. Removes both colliding objects
  /// 5. After 1 second, either respawns ship or triggers game over
  ///
  /// The freeze effect emphasizes the impact and gives players a moment
  /// to process what happened before gameplay resumes.
  ///
  /// [asteroid] The asteroid that hit the ship
  /// [hitShip] The ship that was destroyed
  void onShipAsteroidCollision(Asteroid asteroid, Spaceship hitShip) {
    // Ignore if game is over
    if (!isPlaying) return;
    
    // Don't process collision if ship has invincibility frames active
    if (hitShip.isInvincible) return;

    // Play dramatic explosion sound effect
    Sfx.shipExplosion();

    // Freeze all moving objects for cinematic effect
    // This creates a momentary pause that emphasizes the destruction
    freezeForExplosion = true;

    // Create explosion debris for the ship (white particles)
    add(
      Explosion(
        center: hitShip.position.clone(),  // Explode at ship's position
        color: Colors.white,                // White for ship
        pieceCount: 24,                     // More pieces for bigger effect
        duration: 1.0,                      // 1 second animation
      ),
    );
    
    // Create explosion debris for the asteroid (grey particles)
    add(
      Explosion(
        center: asteroid.position.clone(),  // Explode at asteroid's position
        color: Colors.grey,                 // Grey for asteroid
        pieceCount: 20,                     // Slightly fewer pieces
        duration: 1.0,                      // Match ship explosion duration
      ),
    );

    // Remove both objects from the game (they're destroyed)
    asteroid.removeFromParent();
    hitShip.removeFromParent();

    // Check if player has extra lives remaining
    final bool willRespawn = extraLives > 0;
    if (willRespawn) {
      // Consume one extra life
      extraLives--;
    }

    // Schedule the post-explosion action (respawn or game over)
    // This timer waits for the explosion animation to complete
    add(
      TimerComponent(
        period: 1.0,      // Wait for explosion to finish
        repeat: false,    // Only trigger once
        onTick: () {
          // Unfreeze the game
          freezeForExplosion = false;
          
          // Either respawn the ship or end the game
          if (willRespawn) {
            _respawnShip();
          } else {
            _triggerGameOver();
          }
        },
      ),
    );
  }

  /// Respawns the player's ship after a brief delay
  ///
  /// Creates a new ship at the center of the screen with:
  /// - Position: Screen center
  /// - Velocity: Zero (stationary start)
  /// - Invincibility: 2 seconds (protection from immediate re-death)
  ///
  /// The short 0.1s delay after the explosion allows the game state
  /// to settle before introducing the new ship.
  void _respawnShip() {
    add(
      TimerComponent(
        period: 0.1,      // Very brief delay after explosion
        repeat: false,    // One-time spawn
        onTick: () {
          // Create new ship with invincibility frames
          final newShip = Spaceship()
            ..position = size / 2              // Center of screen
            ..invincibleTime = 2.0;            // 2 seconds of protection
          
          // Update game reference and add to world
          ship = newShip;
          add(newShip);
        },
      ),
    );
  }

  /// Ends the game and displays game over screen
  ///
  /// Sets the game over flag and adds a centered "GAME OVER" text.
  /// Once game over, no more gameplay actions are processed (bullets,
  /// collisions, level advancement, etc.).
  void _triggerGameOver() {
    // Set flag to disable all gameplay
    isGameOver = true;
    
    // Display "GAME OVER" text in screen center
    add(GameOverText());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STARFIELD BACKGROUND - Creates depth and classic arcade atmosphere
// ═══════════════════════════════════════════════════════════════════════════

/// Renders a static starfield background for visual depth
///
/// Creates a field of 200 randomly positioned stars with varying:
/// - Sizes (0.5-2.5 pixels radius)
/// - Brightness (30%-100% opacity)
///
/// The stars are static (don't move), but create a sense of space.
/// Priority -10 ensures stars render behind all game objects.
class Starfield extends Component with HasGameReference<AsteroidsGame> {
  /// Number of stars to generate (default: 200)
  final int starCount;
  
  /// Random number generator for star properties
  final math.Random _rand = math.Random();

  /// Cached star positions (for performance)
  final List<Offset> _positions = [];
  
  /// Cached star radii (for performance)
  final List<double> _radii = [];
  
  /// Cached paint objects for each star (for performance)
  /// Pre-creating these avoids allocating new Paint objects every frame
  final List<Paint> _paints = [];

  /// Creates a starfield with optional custom star count
  Starfield({this.starCount = 200}) {
    // Set render priority to -10 so stars appear behind everything
    priority = -10;
  }

  /// Generates all stars during initialization
  ///
  /// Pre-calculates and caches all star properties for efficient rendering.
  /// This is done once at startup rather than every frame.
  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Get game dimensions for positioning
    final s = game.size;

    // Generate each star with random properties
    for (var i = 0; i < starCount; i++) {
      // Random position within screen bounds
      final x = _rand.nextDouble() * s.x;
      final y = _rand.nextDouble() * s.y;

      // Random size: 0.5 to 2.5 pixels radius
      final radius = 0.5 + _rand.nextDouble() * 2.0;
      
      // Random brightness: 30% to 100% opacity
      // Lower values create dimmer, more distant-looking stars
      final brightness = 0.3 + _rand.nextDouble() * 0.7;

      // Cache all properties for this star
      _positions.add(Offset(x, y));
      _radii.add(radius);
      _paints.add(
        Paint()
          ..color = Colors.white.withValues(alpha: brightness)
          ..style = PaintingStyle.fill,  // Solid circles
      );
    }
  }

  /// Renders all stars to the canvas
  ///
  /// This is called every frame but is very efficient because all
  /// star properties are pre-calculated and cached.
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw each star as a filled circle
    for (var i = 0; i < _positions.length; i++) {
      canvas.drawCircle(_positions[i], _radii[i], _paints[i]);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVES DOCK - Displays remaining extra lives in upper-left corner
// ═══════════════════════════════════════════════════════════════════════════

/// Visual indicator showing how many extra lives the player has remaining
///
/// Displays small ship icons in the upper-left corner:
/// - Each icon represents one extra life (not including current ship)
/// - Icons are simple triangle outlines matching the ship's design
/// - Lives are rendered horizontally with spacing between them
///
/// This gives players constant awareness of their remaining chances.
class LivesDock extends PositionComponent with HasGameReference<AsteroidsGame> {
  /// Creates the lives display at fixed position (10, 10) with space for icons
  LivesDock() : super(position: Vector2(10, 10), size: Vector2(200, 24));

  /// Renders the extra life ship icons
  ///
  /// Draws one triangle for each extra life remaining.
  /// The current ship is not shown here (only extra lives in reserve).
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Get current number of extra lives from game state
    final lives = game.extraLives;

    // Dimensions for each life icon (small triangular ships)
    const double w = 16;       // Width of each ship icon
    const double h = 16;       // Height of each ship icon
    const double spacing = 6;  // Space between icons

    // Paint configuration for drawing ship outlines
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke  // Outline only (no fill)
      ..strokeWidth = 1.4;            // Thin lines like the actual ship

    // Draw each life icon
    for (int i = 0; i < lives; i++) {
      // Calculate X offset for this icon
      final dx = i * (w + spacing);

      // Create triangular ship shape (simplified version of actual ship)
      final path = Path();
      path.moveTo(dx + w / 2, 0);    // Top point (nose)
      path.lineTo(dx + w, h);         // Bottom-right (wing)
      path.lineTo(dx, h);             // Bottom-left (wing)
      path.close();                   // Close path back to top

      // Draw the ship outline
      canvas.drawPath(path, paint);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPACESHIP - Player-controlled ship with vector graphics and physics
// ═══════════════════════════════════════════════════════════════════════════

/// The player's controllable spaceship
///
/// Features:
/// - Rotation: Left/Right arrow keys (3 radians/second)
/// - Thrust: Up arrow key (200 pixels/second² acceleration)
/// - Firing: Spacebar (spawns bullets from ship's nose)
/// - Physics: Momentum-based movement with friction
/// - Wrapping: Screen-edge teleportation for continuous play
/// - Invincibility: Post-respawn protection with visual blinking
///
/// Controls:
/// - ← Left Arrow: Rotate counterclockwise
/// - → Right Arrow: Rotate clockwise  
/// - ↑ Up Arrow: Apply forward thrust
/// - Space: Fire bullet
///
/// The ship uses vector graphics (polygon outline) for classic arcade style.
class Spaceship extends PositionComponent
    with KeyboardHandler, HasGameReference<AsteroidsGame>, CollisionCallbacks {
  
  /// Rotation speed in radians per second
  final double rotationSpeed = 3.0;
  
  /// Forward thrust acceleration in pixels per second²
  final double thrust = 200.0;

  /// Current velocity vector (momentum)
  /// Persists between frames to create realistic physics
  Vector2 velocity = Vector2.zero();
  
  /// Flag: Ship is rotating left (Left Arrow held)
  bool turningLeft = false;
  
  /// Flag: Ship is rotating right (Right Arrow held)
  bool turningRight = false;
  
  /// Flag: Ship is accelerating forward (Up Arrow held)
  bool accelerating = false;

  /// Time remaining for invincibility (in seconds)
  /// Set to 2.0 on respawn, decrements each frame
  double invincibleTime = 0;
  
  /// Convenience getter to check if ship has active invincibility
  bool get isInvincible => invincibleTime > 0;

  /// Creates a 40x40 pixel ship centered on its anchor point
  Spaceship() : super(size: Vector2(40, 40), anchor: Anchor.center);

  /// Initializes the ship's visual appearance and collision detection
  ///
  /// Creates:
  /// 1. Ship polygon (9-point vector outline forming a classic spaceship shape)
  /// 2. Visual component (white stroke polygon)
  /// 3. Collision hitbox (matching the ship's polygon shape)
  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Start at screen center
    position = game.size / 2;

    // Define ship shape as 9 points (normalized -1 to 1 coordinates)
    // Points form a classic arrowhead/triangle shape with extended body
    final List<Vector2> shipPoints = [
      Vector2(0.0, -1.0),    // Nose (top center)
      Vector2(0.25, -0.3),   // Right upper hull
      Vector2(0.6, 0.4),     // Right mid-body
      Vector2(0.3, 0.9),     // Right lower body
      Vector2(0.15, 1.0),    // Right engine
      Vector2(-0.15, 1.0),   // Left engine
      Vector2(-0.3, 0.9),    // Left lower body
      Vector2(-0.6, 0.4),    // Left mid-body
      Vector2(-0.25, -0.3),  // Left upper hull
    ];

    // Create visual representation of the ship
    final hull = PolygonComponent.relative(
      shipPoints,
      parentSize: size,
      paint: Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke  // Outline only (vector style)
        ..strokeWidth = 2,              // Visible but not too thick
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    // Add visual component to ship
    add(hull);

    // Create collision hitbox matching the ship's shape
    // This enables accurate collision detection with asteroids and bullets
    add(
      PolygonHitbox.relative(
        shipPoints,
        parentSize: size,
      ),
    );
  }

  /// Updates ship physics, rotation, and position each frame
  ///
  /// Handles:
  /// - Invincibility timer countdown
  /// - Rotation based on input
  /// - Thrust acceleration
  /// - Momentum and friction
  /// - Screen edge wrapping
  ///
  /// [dt] Delta time (time since last frame in seconds)
  @override
  void update(double dt) {
    super.update(dt);

    // Freeze ship during game over or explosion sequence
    if (!game.isPlaying || game.freezeForExplosion) return;

    // Count down invincibility timer
    if (invincibleTime > 0) {
      invincibleTime -= dt;
      if (invincibleTime < 0) invincibleTime = 0;  // Clamp at zero
    }

    // Apply rotation based on input flags
    if (turningLeft) angle -= rotationSpeed * dt;
    if (turningRight) angle += rotationSpeed * dt;

    // Apply forward thrust if accelerating
    if (accelerating) {
      // Calculate forward direction based on current rotation
      // Vector2(0, -1) points up, then rotated to ship's angle
      final direction = Vector2(0, -1)..rotate(angle);
      
      // Add acceleration to velocity (momentum-based physics)
      velocity += direction * thrust * dt;
    }

    // Update position based on current velocity (momentum)
    position += velocity * dt;

    // Apply friction when not accelerating (drift to a stop)
    if (!accelerating) {
      velocity *= 0.95;  // Reduce velocity by 5% each frame
      
      // Stop completely when velocity is very small
      if (velocity.length < 1) velocity = Vector2.zero();
    }

    // Screen edge wrapping (teleport to opposite side)
    final s = game.size;
    
    // Wrap horizontal edges
    if (position.x < 0) position.x += s.x;       // Left edge → Right
    if (position.x > s.x) position.x -= s.x;     // Right edge → Left
    
    // Wrap vertical edges
    if (position.y < 0) position.y += s.y;       // Top edge → Bottom
    if (position.y > s.y) position.y -= s.y;     // Bottom edge → Top
  }

  /// Renders the ship (with blinking effect during invincibility)
  ///
  /// During invincibility, the ship blinks on/off at 10Hz to provide
  /// visual feedback that the player is protected from collisions.
  @override
  void render(Canvas canvas) {
    // Blink effect during invincibility period
    if (invincibleTime > 0) {
      // Calculate blink state (10 times per second)
      final t = (invincibleTime * 10).floor();
      
      // Don't render on even frames (creates blink effect)
      if (t.isEven) return;
    }
    
    // Normal rendering
    super.render(canvas);
  }

  /// Handles keyboard input for ship controls
  ///
  /// Processes:
  /// - Arrow keys for rotation and thrust (continuous while held)
  /// - Spacebar for firing bullets (on key press only)
  ///
  /// Returns true to indicate the event was handled.
  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Ignore input during game over or explosion freeze
    if (!game.isPlaying || game.freezeForExplosion) return false;

    // Update control flags based on currently pressed keys
    turningLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    turningRight = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    accelerating = keysPressed.contains(LogicalKeyboardKey.arrowUp);

    // Fire bullet on spacebar press (not on hold)
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      // Calculate bullet spawn position (at ship's nose)
      final dir = Vector2(0, -1)..rotate(angle);
      final bulletPos = position + dir * (size.y / 2);
      
      // Spawn bullet through game's spawn system
      game.spawnBullet(bulletPos, angle);
    }
    
    return true;  // Event handled
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BULLETS - Projectiles fired from the ship
// ═══════════════════════════════════════════════════════════════════════════

/// Bullet projectile that destroys asteroids
///
/// Properties:
/// - Speed: 400 pixels/second (constant)
/// - Appearance: Small yellow circle (3px radius)
/// - Lifespan: Until it leaves the screen
/// - Collision: Destroys on contact with asteroids
///
/// Bullets travel in straight lines and don't wrap around screen edges.
class Bullet extends CircleComponent
    with CollisionCallbacks, HasGameReference<AsteroidsGame> {
  
  /// Bullet travel speed in pixels per second
  final double speed = 400.0;
  
  /// Velocity vector (direction and speed combined)
  /// Calculated in constructor from firing angle
  late final Vector2 velocity;

  /// Creates a bullet fired at the specified angle
  ///
  /// [angle] Direction to fire (in radians, 0 = right, π/2 = down)
  Bullet({required double angle})
      : super(
          radius: 3,                         // Small yellow dot
          paint: Paint()..color = Colors.yellow,
        ) {
    // Calculate velocity from angle and speed
    // Vector2(0, -1) points up, then rotated to firing angle
    velocity = (Vector2(0, -1)..rotate(angle)) * speed;
  }

  /// Adds collision detection to the bullet
  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Add circular hitbox for collision detection with asteroids
    add(CircleHitbox());
  }

  /// Moves the bullet and removes it when it leaves the screen
  ///
  /// Unlike the ship and asteroids, bullets don't wrap around edges.
  /// They're removed to conserve memory and processing power.
  ///
  /// [dt] Delta time (time since last frame in seconds)
  @override
  void update(double dt) {
    super.update(dt);

    // Freeze bullets during game over or explosion
    if (!game.isPlaying || game.freezeForExplosion) return;

    // Move bullet forward based on velocity
    position += velocity * dt;

    // Check if bullet has left the screen
    final s = game.size;
    if (position.x < 0 ||      // Left edge
        position.x > s.x ||    // Right edge
        position.y < 0 ||      // Top edge
        position.y > s.y) {    // Bottom edge
      // Remove from game to free resources
      removeFromParent();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ASTEROIDS - Procedurally generated space rocks with splitting mechanics
// ═══════════════════════════════════════════════════════════════════════════

/// Destructible asteroid that splits when hit
///
/// Key Features:
/// - Three size levels: Large (60px), Medium (40px), Small (24px)
/// - Procedurally generated jagged shapes (each unique)
/// - Splitting: Large → 2 Medium, Medium → 2 Small, Small → destroyed
/// - Constant velocity (straight-line movement)
/// - Screen-edge wrapping (teleports to opposite side)
/// - Collision detection with bullets and ship
///
/// Design Philosophy:
/// The random shape generation ensures no two asteroids look identical,
/// adding visual variety and authenticity to the arcade experience.
class Asteroid extends PositionComponent
    with CollisionCallbacks, HasGameReference<AsteroidsGame> {
  /// Size tier: 2 = Large (60px), 1 = Medium (40px), 0 = Small (24px)
  /// Determines visual size and whether asteroid splits when destroyed
  final int sizeLevel;
  
  /// Movement velocity in pixels per second
  /// Set randomly at spawn, remains constant (asteroids don't accelerate)
  Vector2 velocity;
  
  /// Random number generator for shape creation
  /// Each asteroid gets unique random jagged edges
  final math.Random _rand = math.Random();
  
  /// List of normalized points (-1 to 1) defining the asteroid's polygon shape
  /// Generated procedurally to create unique, irregular rock formations
  late final List<Vector2> shape;

  /// Creates an asteroid with specified size and velocity
  ///
  /// [sizeLevel] Size tier (2=large, 1=medium, 0=small)
  /// [velocity] Movement direction and speed
  Asteroid({
    required this.sizeLevel,
    required this.velocity,
  }) : super(anchor: Anchor.center);

  /// Returns the diameter in pixels for a given size level
  ///
  /// Size progression follows classic Asteroids scaling:
  /// - Level 2 (Large): 60px - Initial spawn size
  /// - Level 1 (Medium): 40px - 2/3 of large size
  /// - Level 0 (Small): 24px - 40% of large size
  ///
  /// This 60→40→24 progression creates clear visual distinction
  /// between asteroid generations while maintaining gameplay balance.
  static double sizeForLevel(int level) {
    switch (level) {
      case 2:
        return 60;   // Large asteroids (initial spawn)
      case 1:
        return 40;   // Medium asteroids (first split)
      default:
        return 24;   // Small asteroids (second split, smallest)
    }
  }

  /// Initializes the asteroid's appearance and collision detection
  ///
  /// Process:
  /// 1. Set size based on level (60/40/24 pixels)
  /// 2. Generate unique jagged polygon shape
  /// 3. Create visual representation (grey polygon outline)
  /// 4. Add collision hitbox matching the shape
  ///
  /// The procedural shape generation ensures visual variety - no two
  /// asteroids look exactly alike, even at the same size level.
  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Set asteroid dimensions based on size level
    size = Vector2.all(sizeForLevel(sizeLevel));

    // Generate unique random jagged shape (10-14 irregular points)
    shape = _generateJaggedShape();

    // Create visual polygon component (grey outline)
    final poly = PolygonComponent.relative(
      shape,
      parentSize: size,
      paint: Paint()..color = Colors.grey,  // Classic asteroid grey
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    // Add visual representation to asteroid
    add(poly);

    // Add collision hitbox matching the irregular shape
    // This ensures accurate hit detection that follows the jagged edges
    add(
      PolygonHitbox.relative(
        shape,
        parentSize: size,
      ),
    );
  }

  /// Generates a random jagged polygon shape for the asteroid
  ///
  /// Creates an irregular rock-like shape using polar coordinates:
  /// 1. Generate 10-14 random points (n) around a circle
  /// 2. For each point, vary the radius randomly (70%-100%)
  /// 3. Convert polar coordinates to Cartesian (x, y)
  ///
  /// Algorithm Details:
  /// - Points are evenly spaced by angle: 360° / n
  /// - Radius varies randomly: 0.7 to 1.0 (normalized)
  /// - cos(angle) * r = X coordinate
  /// - sin(angle) * r = Y coordinate
  ///
  /// Result: Each asteroid has unique jagged edges that look natural
  /// and irregular, mimicking real space rocks.
  ///
  /// Returns normalized points (range -1 to 1) that scale to asteroid size.
  List<Vector2> _generateJaggedShape() {
    // Random point count: 10-14 vertices for variety
    final int n = 10 + _rand.nextInt(5);
    final List<Vector2> pts = [];

    // Generate each point using polar coordinates
    for (int i = 0; i < n; i++) {
      // Calculate angle for this point (evenly distributed around circle)
      final angle = (2 * math.pi * i) / n;
      
      // Random radius: 0.7 to 1.0 (creates jagged irregular edges)
      final r = 0.7 + _rand.nextDouble() * 0.3;

      // Convert polar to Cartesian and add to shape
      // Normalized coordinates (-1 to 1) scale to actual size in rendering
      pts.add(Vector2(math.cos(angle) * r, math.sin(angle) * r));
    }

    return pts;
  }

  /// Updates asteroid position and handles screen-edge wrapping
  ///
  /// Movement characteristics:
  /// - Constant velocity (no acceleration or deceleration)
  /// - Straight-line trajectory (angle never changes)
  /// - Screen wrapping (teleports to opposite edge)
  ///
  /// Physics:
  /// - position += velocity * dt (simple linear motion)
  /// - No friction or drag (this is space!)
  /// - No rotation animation (keeps classic arcade feel)
  ///
  /// [dt] Delta time (seconds since last frame)
  @override
  void update(double dt) {
    super.update(dt);

    // Freeze during game over or explosion cinematic
    if (!game.isPlaying || game.freezeForExplosion) return;

    // Move asteroid along its velocity vector
    position += velocity * dt;

    // Screen-edge wrapping (seamless teleportation)
    final s = game.size;
    
    // Horizontal wrapping
    if (position.x < 0) position.x += s.x;       // Left → Right
    if (position.x > s.x) position.x -= s.x;     // Right → Left
    
    // Vertical wrapping
    if (position.y < 0) position.y += s.y;       // Top → Bottom
    if (position.y > s.y) position.y -= s.y;     // Bottom → Top
  }

  /// Handles collisions with bullets and the spaceship
  ///
  /// Two collision types:
  /// 1. Bullet collision:
  ///    - Destroys the bullet (removes it from game)
  ///    - Plays asteroid hit sound
  ///    - Splits asteroid if not smallest size (sizeLevel > 0)
  ///    - Removes this asteroid from game
  ///
  /// 2. Spaceship collision:
  ///    - Delegates to game's collision handler
  ///    - Game handles explosion effects, lives, and respawn
  ///    - Checks invincibility to prevent unfair hits
  ///
  /// [intersectionPoints] Points where collision occurred (unused but required)
  /// [other] The component this asteroid collided with
  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    // Handle bullet collision
    if (other is Bullet) {
      // Remove bullet from game (it's destroyed on impact)
      other.removeFromParent();

      // Play satisfying asteroid destruction sound
      Sfx.asteroidHit();

      // Split into smaller asteroids if not already smallest
      // sizeLevel 2 (large) or 1 (medium) will split
      // sizeLevel 0 (small) just gets destroyed
      if (sizeLevel > 0) {
        game.splitAsteroid(this);
      }

      // Remove this asteroid (it's been destroyed)
      removeFromParent();
    }

    // Handle spaceship collision
    if (other is Spaceship) {
      // Let the game handle ship destruction (explosion, lives, etc.)
      game.onShipAsteroidCollision(this, other);
    }

    super.onCollision(intersectionPoints, other);
  }

  /// Called when this asteroid is removed from the game
  ///
  /// Notifies the game that an asteroid has been destroyed so it can:
  /// - Decrement the asteroid counter
  /// - Check if level is complete (all asteroids destroyed)
  /// - Advance to next level if appropriate
  ///
  /// This is called automatically by the Flame engine when
  /// removeFromParent() is invoked.
  @override
  void onRemove() {
    // Tell game to update asteroid count and check for level completion
    game.onAsteroidDestroyed();
    super.onRemove();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPLOSION - Particle effect system for dramatic destruction sequences
// ═══════════════════════════════════════════════════════════════════════════

/// Explosion particle effect that creates dramatic debris
///
/// Features:
/// - Configurable number of particles (debris pieces)
/// - Random velocity in all directions (radial burst)
/// - Fade-out effect (alpha decreases over time)
/// - Velocity dampening (particles slow down gradually)
/// - Customizable color and duration
///
/// Usage:
/// - Ship explosions: White particles, 24 pieces, 1.0s duration
/// - Asteroid explosions: Grey particles, 20 pieces, 1.0s duration
///
/// Physics:
/// - Initial speed: 60-200 pixels/second (random per particle)
/// - Dampening: 10% velocity reduction per frame (0.9 multiplier)
/// - Fadeout: Linear alpha interpolation from 255 to 0
class Explosion extends PositionComponent {
  /// Number of debris pieces to create (more = denser explosion)
  final int pieceCount;
  
  /// How long the explosion lasts in seconds before auto-removal
  final double duration;
  
  /// Color of the debris particles (white for ship, grey for asteroid)
  final Color color;
  
  /// Random number generator for particle velocities and sizes
  final math.Random _rand = math.Random();

  /// List of all explosion particles with their properties
  final List<_ExplosionPiece> _pieces = [];
  
  /// Elapsed time since explosion started (used for fadeout calculation)
  double _time = 0;

  /// Creates an explosion at the specified center point
  ///
  /// [center] Position where explosion originates
  /// [pieceCount] Number of debris pieces (default: 20)
  /// [duration] Effect duration in seconds (default: 0.8)
  /// [color] Particle color (default: white)
  Explosion({
    required Vector2 center,
    this.pieceCount = 20,
    this.duration = 0.8,
    this.color = Colors.white,
  }) : super(position: center, anchor: Anchor.center);

  /// Generates all explosion particles during initialization
  ///
  /// Creates a radial burst pattern where particles fly outward in all
  /// directions from the explosion center. Each particle has:
  /// - Random angle (0 to 2π radians for full 360° coverage)
  /// - Random speed (60-200 pixels/second for variation)
  /// - Random size (2-6 pixels for visual variety)
  ///
  /// The velocity is calculated using polar-to-Cartesian conversion:
  /// - vx = cos(angle) × speed (horizontal component)
  /// - vy = sin(angle) × speed (vertical component)
  ///
  /// This creates a realistic explosion effect where debris scatters
  /// in all directions at varying speeds.
  @override
  Future<void> onLoad() async {
    super.onLoad();

    // Create each explosion particle
    for (int i = 0; i < pieceCount; i++) {
      // Random direction (full 360° coverage)
      final angle = _rand.nextDouble() * 2 * math.pi;
      
      // Random speed (60-200 px/s creates varied scatter)
      final speed = 60 + _rand.nextDouble() * 140;
      
      // Convert polar coordinates to Cartesian velocity
      final vx = math.cos(angle) * speed;  // X velocity component
      final vy = math.sin(angle) * speed;  // Y velocity component
      
      // Random particle size (2-6 pixels)
      final size = 2.0 + _rand.nextDouble() * 4.0;

      // Add particle to explosion
      _pieces.add(
        _ExplosionPiece(
          offset: Vector2.zero(),           // Start at center
          velocity: Vector2(vx, vy),        // Outward velocity
          size: size,                       // Visual size
        ),
      );
    }
  }

  /// Updates all particles and handles explosion lifecycle
  ///
  /// Each frame:
  /// 1. Increments elapsed time counter
  /// 2. Moves each particle based on its velocity
  /// 3. Applies dampening (slows particles by 10%)
  /// 4. Removes explosion when duration expires
  ///
  /// Dampening effect:
  /// - Multiplying velocity by 0.9 each frame creates deceleration
  /// - Particles start fast and gradually slow down
  /// - This looks more realistic than constant-speed particles
  ///
  /// [dt] Delta time (seconds since last frame)
  @override
  void update(double dt) {
    super.update(dt);

    // Track elapsed time for fadeout calculation
    _time += dt;
    
    // Update each particle
    for (final p in _pieces) {
      // Move particle based on current velocity
      p.offset += p.velocity * dt;
      
      // Apply dampening (10% slowdown per frame)
      // Creates realistic deceleration effect
      p.velocity *= 0.9;
    }

    // Remove explosion when animation is complete
    if (_time >= duration) {
      removeFromParent();
    }
  }

  /// Renders all particles with fadeout effect
  ///
  /// Visual effects:
  /// - Linear fadeout: Alpha goes from 255 (opaque) to 0 (transparent)
  /// - All particles share same alpha (synchronized fade)
  /// - Particles drawn as small rectangles
  ///
  /// Fadeout calculation:
  /// - progress = time / duration (0.0 to 1.0)
  /// - alpha = 255 × (1.0 - progress)
  /// - At start: progress=0, alpha=255 (fully visible)
  /// - At end: progress=1, alpha=0 (invisible)
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Calculate fade progress (0.0 = start, 1.0 = end)
    final progress = (_time / duration).clamp(0.0, 1.0);
    
    // Calculate current alpha (255 to 0, linear interpolation)
    final alpha = (255 * (1.0 - progress)).toInt();

    // Create paint with fading color
    final paint = Paint()
      ..color = color.withAlpha(alpha)  // Decreasing transparency
      ..style = PaintingStyle.fill;     // Solid particles

    // Draw each debris piece
    for (final p in _pieces) {
      // Create rectangular particle at current position
      final rect = Rect.fromCenter(
        center: Offset(p.offset.x, p.offset.y),
        width: p.size,
        height: p.size,
      );
      // Render the particle
      canvas.drawRect(rect, paint);
    }
  }
}

/// Private data class representing a single explosion particle
///
/// Each piece tracks its own:
/// - Position offset from explosion center
/// - Velocity vector (direction and speed)
/// - Visual size in pixels
///
/// This is a simple mutable data holder - the Explosion component
/// manages updating these properties each frame.
class _ExplosionPiece {
  /// Current position offset from explosion center
  /// Updated each frame: offset += velocity × deltaTime
  Vector2 offset;
  
  /// Movement velocity in pixels per second
  /// Decreases over time due to dampening (× 0.9 per frame)
  Vector2 velocity;
  
  /// Visual size of this particle in pixels (width and height)
  /// Randomized at creation (2-6 pixels), remains constant
  double size;

  /// Creates a particle with specified properties
  _ExplosionPiece({
    required this.offset,
    required this.velocity,
    required this.size,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GAME OVER TEXT - Final screen message when player loses all lives
// ═══════════════════════════════════════════════════════════════════════════

/// Displays "GAME OVER" text centered on screen
///
/// Appearance:
/// - Text: "GAME OVER" in all caps
/// - Font size: 32 pixels
/// - Style: Bold, white color
/// - Position: Exact center of screen
///
/// Behavior:
/// - Appears when player loses final life
/// - Remains visible indefinitely (no auto-dismiss)
/// - Static (no animation or effects)
///
/// This is the terminal state of the game - no further gameplay
/// actions are processed once this appears. Player must restart
/// the application to play again.
class GameOverText extends TextComponent with HasGameReference<AsteroidsGame> {
  /// Creates the game over text with fixed styling
  ///
  /// Text rendering configuration:
  /// - Font size: 32px (large and prominent)
  /// - Weight: Bold (emphasizes finality)
  /// - Color: White (high contrast on black background)
  /// - Anchor: Center (for perfect centering)
  GameOverText()
      : super(
          text: "GAME OVER",
          textRenderer: TextPaint(
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          anchor: Anchor.center,  // Center anchor for positioning
        );

  /// Positions the text at the exact center of the screen
  ///
  /// The center anchor combined with center position ensures the
  /// text is perfectly centered both horizontally and vertically.
  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Place at screen center (game.size / 2)
    position = game.size / 2;
  }
}

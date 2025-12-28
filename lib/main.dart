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
import 'package:flame/collisions.dart'; // Collision detection system
import 'package:flame/components.dart'; // Game components (sprites, shapes, etc.)
import 'package:flame/game.dart'; // Core game loop and engine
import 'package:flame/input.dart'; // Keyboard/touch input handling
import 'package:flame/text.dart'; // Text rendering components
import 'package:flame_audio/flame_audio.dart'; // Audio playback system

// Flutter framework imports
import 'package:flutter/material.dart'; // UI widgets and material design
import 'package:flutter/services.dart'; // Keyboard key constants

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
          autofocus: true, // Automatically focus on game start
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
  /// [position] Starting position (typically ship's nose)
  /// [angle] Direction to fire (in radians, ship's rotation)
  void spawnBullet(Vector2 position, double angle) {
    // Don't spawn bullets if game is over or during explosion freeze
    if (!isPlaying || freezeForExplosion) return;

    // Create bullet with specified angle and properties
    final bullet = Bullet(angle: angle)
      ..position = position // Start at ship's position
      ..anchor = Anchor.center; // Center anchor for collision detection

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
  void spawnAsteroid({
    required int sizeLevel,
    Vector2? position,
    Vector2? velocity,
  }) {
    // Generate random velocity if not provided
    final vel = velocity ??
        Vector2(
          (_rand.nextDouble() - 0.5) * 120,
          (_rand.nextDouble() - 0.5) * 120,
        );

    // Create asteroid with specified properties
    final asteroid = Asteroid(
      sizeLevel: sizeLevel,
      velocity: vel,
    )
      ..position = position ??
          Vector2(
            _rand.nextDouble() * size.x,
            _rand.nextDouble() * size.y,
          )
      ..anchor = Anchor.center;

    asteroidCount++;
    add(asteroid);
  }

  /// Splits a destroyed asteroid into two smaller asteroids
  void splitAsteroid(Asteroid parent) {
    final newLevel = parent.sizeLevel - 1;
    if (newLevel < 0) return;

    for (var i = 0; i < 2; i++) {
      final angle = _rand.nextDouble() * math.pi * 2;
      final speed = 80 + _rand.nextDouble() * 60;
      final vel = Vector2(math.cos(angle), math.sin(angle)) * speed;

      spawnAsteroid(
        sizeLevel: newLevel,
        position: parent.position.clone(),
        velocity: vel,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LEVEL MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Called when an asteroid is removed from the game
  void onAsteroidDestroyed() {
    if (!isPlaying) return;

    asteroidCount--;

    if (asteroidCount <= 0) {
      nextLevel();
    }
  }

  /// Spawns asteroids for the current level
  void startLevel() {
    final center = size / 2;

    final double ringRadius =
        (math.min(size.x, size.y) * 0.35).clamp(80.0, 400.0).toDouble();

    for (var i = 0; i < level; i++) {
      final angle = (2 * math.pi * i) / level;
      final dir = Vector2(math.cos(angle), math.sin(angle));
      final pos = center + dir * ringRadius;

      final tangentAngle = angle + math.pi / 2;
      final speed = 60 + _rand.nextDouble() * 80;
      final vel =
          Vector2(math.cos(tangentAngle), math.sin(tangentAngle)) * speed;

      spawnAsteroid(
        sizeLevel: 2,
        position: pos,
        velocity: vel,
      );
    }
  }

  /// Advances to the next level
  void nextLevel() {
    level++;

    if (ship != null && ship!.parent != null) {
      ship!
        ..position = size / 2
        ..velocity = Vector2.zero()
        ..angle = 0;
    }

    startLevel();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // COLLISION & RESPAWN HANDLING
  // ═══════════════════════════════════════════════════════════════════════

  /// Handles the collision between ship and asteroid with cinematic effect
  void onShipAsteroidCollision(Asteroid asteroid, Spaceship hitShip) {
    if (!isPlaying) return;
    if (hitShip.isInvincible) return;

    // Play explosion SFX
    Sfx.shipExplosion();

    // Freeze movement during explosion
    freezeForExplosion = true;

    // Ship explosion
    add(
      Explosion(
        center: hitShip.position.clone(),
        color: Colors.white,
        pieceCount: 24,
        duration: 1.0,
      ),
    );

    // Asteroid explosion
    add(
      Explosion(
        center: asteroid.position.clone(),
        color: Colors.grey,
        pieceCount: 20,
        duration: 1.0,
      ),
    );

    asteroid.removeFromParent();
    hitShip.removeFromParent();

    final bool willRespawn = extraLives > 0;
    if (willRespawn) {
      extraLives--;
    }

    add(
      TimerComponent(
        period: 1.0,
        repeat: false,
        onTick: () {
          freezeForExplosion = false;
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
  void _respawnShip() {
    add(
      TimerComponent(
        period: 0.1,
        repeat: false,
        onTick: () {
          final newShip = Spaceship()
            ..position = size / 2
            ..invincibleTime = 2.0;
          ship = newShip;
          add(newShip);
        },
      ),
    );
  }

  /// Ends the game and displays game over screen
  void _triggerGameOver() {
    isGameOver = true;
    add(GameOverText());
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STARFIELD BACKGROUND - Responsive to window size
// ═══════════════════════════════════════════════════════════════════════════

/// Renders a starfield background that resizes with the window.
///
/// Whenever the game window is resized, the starfield regenerates its
/// stars to fill the new dimensions so there are no empty bands.
class Starfield extends Component with HasGameReference<AsteroidsGame> {
  /// Number of stars to generate (default: 200)
  final int starCount;

  /// Random number generator for star properties
  final math.Random _rand = math.Random();

  /// Cached star positions
  final List<Offset> _positions = [];

  /// Cached star radii
  final List<double> _radii = [];

  /// Cached paint objects for each star
  final List<Paint> _paints = [];

  Starfield({this.starCount = 200}) {
    priority = -10; // Render behind everything
  }

  /// Helper to (re)generate stars for the current game size
  void _generateStars(Vector2 size) {
    _positions.clear();
    _radii.clear();
    _paints.clear();

    final width = size.x;
    final height = size.y;

    if (width <= 0 || height <= 0) {
      return;
    }

    for (var i = 0; i < starCount; i++) {
      final x = _rand.nextDouble() * width;
      final y = _rand.nextDouble() * height;

      final radius = 0.5 + _rand.nextDouble() * 2.0;
      final brightness = 0.3 + _rand.nextDouble() * 0.7;

      _positions.add(Offset(x, y));
      _radii.add(radius);
      _paints.add(
        Paint()
          ..color = Colors.white.withOpacity(brightness)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    _generateStars(game.size);
  }

  /// Called whenever the game/canvas size changes
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _generateStars(size);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (var i = 0; i < _positions.length; i++) {
      canvas.drawCircle(_positions[i], _radii[i], _paints[i]);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LIVES DOCK - Displays remaining extra lives in upper-left corner
// ═══════════════════════════════════════════════════════════════════════════

/// Visual indicator showing how many extra lives the player has remaining
class LivesDock extends PositionComponent with HasGameReference<AsteroidsGame> {
  LivesDock() : super(position: Vector2(10, 10), size: Vector2(200, 24));

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final lives = game.extraLives;

    const double w = 16;
    const double h = 16;
    const double spacing = 6;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (int i = 0; i < lives; i++) {
      final dx = i * (w + spacing);

      final path = Path();
      path.moveTo(dx + w / 2, 0);
      path.lineTo(dx + w, h);
      path.lineTo(dx, h);
      path.close();

      canvas.drawPath(path, paint);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPACESHIP - Player-controlled ship with vector graphics and physics
// ═══════════════════════════════════════════════════════════════════════════

class Spaceship extends PositionComponent
    with KeyboardHandler, HasGameReference<AsteroidsGame>, CollisionCallbacks {
  final double rotationSpeed = 3.0;
  final double thrust = 200.0;

  Vector2 velocity = Vector2.zero();
  bool turningLeft = false;
  bool turningRight = false;
  bool accelerating = false;

  double invincibleTime = 0;
  bool get isInvincible => invincibleTime > 0;

  Spaceship() : super(size: Vector2(40, 40), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();

    position = game.size / 2;

    final List<Vector2> shipPoints = [
      Vector2(0.0, -1.0),
      Vector2(0.25, -0.3),
      Vector2(0.6, 0.4),
      Vector2(0.3, 0.9),
      Vector2(0.15, 1.0),
      Vector2(-0.15, 1.0),
      Vector2(-0.3, 0.9),
      Vector2(-0.6, 0.4),
      Vector2(-0.25, -0.3),
    ];

    final hull = PolygonComponent.relative(
      shipPoints,
      parentSize: size,
      paint: Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    add(hull);

    add(
      PolygonHitbox.relative(
        shipPoints,
        parentSize: size,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!game.isPlaying || game.freezeForExplosion) return;

    if (invincibleTime > 0) {
      invincibleTime -= dt;
      if (invincibleTime < 0) invincibleTime = 0;
    }

    if (turningLeft) angle -= rotationSpeed * dt;
    if (turningRight) angle += rotationSpeed * dt;

    if (accelerating) {
      final direction = Vector2(0, -1)..rotate(angle);
      velocity += direction * thrust * dt;
    }

    position += velocity * dt;

    if (!accelerating) {
      velocity *= 0.95;
      if (velocity.length < 1) velocity = Vector2.zero();
    }

    final s = game.size;

    if (position.x < 0) position.x += s.x;
    if (position.x > s.x) position.x -= s.x;
    if (position.y < 0) position.y += s.y;
    if (position.y > s.y) position.y -= s.y;
  }

  @override
  void render(Canvas canvas) {
    if (invincibleTime > 0) {
      final t = (invincibleTime * 10).floor();
      if (t.isEven) return;
    }
    super.render(canvas);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!game.isPlaying || game.freezeForExplosion) return false;

    turningLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    turningRight = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    accelerating = keysPressed.contains(LogicalKeyboardKey.arrowUp);

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      final dir = Vector2(0, -1)..rotate(angle);
      final bulletPos = position + dir * (size.y / 2);
      game.spawnBullet(bulletPos, angle);
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BULLETS - Projectiles fired from the ship
// ═══════════════════════════════════════════════════════════════════════════

class Bullet extends CircleComponent
    with CollisionCallbacks, HasGameReference<AsteroidsGame> {
  final double speed = 400.0;
  late final Vector2 velocity;

  Bullet({required double angle})
      : super(
          radius: 3,
          paint: Paint()..color = Colors.yellow,
        ) {
    velocity = (Vector2(0, -1)..rotate(angle)) * speed;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!game.isPlaying || game.freezeForExplosion) return;

    position += velocity * dt;

    final s = game.size;
    if (position.x < 0 ||
        position.x > s.x ||
        position.y < 0 ||
        position.y > s.y) {
      removeFromParent();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ASTEROIDS - Procedurally generated space rocks with splitting mechanics
// ═══════════════════════════════════════════════════════════════════════════

class Asteroid extends PositionComponent
    with CollisionCallbacks, HasGameReference<AsteroidsGame> {
  final int sizeLevel;
  Vector2 velocity;
  final math.Random _rand = math.Random();
  late final List<Vector2> shape;

  Asteroid({
    required this.sizeLevel,
    required this.velocity,
  }) : super(anchor: Anchor.center);

  static double sizeForLevel(int level) {
    switch (level) {
      case 2:
        return 60;
      case 1:
        return 40;
      default:
        return 24;
    }
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    size = Vector2.all(sizeForLevel(sizeLevel));

    shape = _generateJaggedShape();

    final poly = PolygonComponent.relative(
      shape,
      parentSize: size,
      paint: Paint()..color = Colors.grey,
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    add(poly);

    add(
      PolygonHitbox.relative(
        shape,
        parentSize: size,
      ),
    );
  }

  List<Vector2> _generateJaggedShape() {
    final int n = 10 + _rand.nextInt(5);
    final List<Vector2> pts = [];

    for (int i = 0; i < n; i++) {
      final angle = (2 * math.pi * i) / n;
      final r = 0.7 + _rand.nextDouble() * 0.3;

      pts.add(Vector2(math.cos(angle) * r, math.sin(angle) * r));
    }

    return pts;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!game.isPlaying || game.freezeForExplosion) return;

    position += velocity * dt;

    final s = game.size;
    if (position.x < 0) position.x += s.x;
    if (position.x > s.x) position.x -= s.x;
    if (position.y < 0) position.y += s.y;
    if (position.y > s.y) position.y -= s.y;
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Bullet) {
      other.removeFromParent();

      Sfx.asteroidHit();

      if (sizeLevel > 0) {
        game.splitAsteroid(this);
      }

      removeFromParent();
    }

    if (other is Spaceship) {
      game.onShipAsteroidCollision(this, other);
    }

    super.onCollision(intersectionPoints, other);
  }

  @override
  void onRemove() {
    game.onAsteroidDestroyed();
    super.onRemove();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPLOSION - Particle effect system for dramatic destruction sequences
// ═══════════════════════════════════════════════════════════════════════════

class Explosion extends PositionComponent {
  final int pieceCount;
  final double duration;
  final Color color;
  final math.Random _rand = math.Random();

  final List<_ExplosionPiece> _pieces = [];
  double _time = 0;

  Explosion({
    required Vector2 center,
    this.pieceCount = 20,
    this.duration = 0.8,
    this.color = Colors.white,
  }) : super(position: center, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();

    for (int i = 0; i < pieceCount; i++) {
      final angle = _rand.nextDouble() * 2 * math.pi;
      final speed = 60 + _rand.nextDouble() * 140;

      final vx = math.cos(angle) * speed;
      final vy = math.sin(angle) * speed;

      final size = 2.0 + _rand.nextDouble() * 4.0;

      _pieces.add(
        _ExplosionPiece(
          offset: Vector2.zero(),
          velocity: Vector2(vx, vy),
          size: size,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    _time += dt;

    for (final p in _pieces) {
      p.offset += p.velocity * dt;
      p.velocity *= 0.9;
    }

    if (_time >= duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final progress = (_time / duration).clamp(0.0, 1.0);
    final alpha = (255 * (1.0 - progress)).toInt();

    final paint = Paint()
      ..color = color.withAlpha(alpha)
      ..style = PaintingStyle.fill;

    for (final p in _pieces) {
      final rect = Rect.fromCenter(
        center: Offset(p.offset.x, p.offset.y),
        width: p.size,
        height: p.size,
      );
      canvas.drawRect(rect, paint);
    }
  }
}

class _ExplosionPiece {
  Vector2 offset;
  Vector2 velocity;
  double size;

  _ExplosionPiece({
    required this.offset,
    required this.velocity,
    required this.size,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// GAME OVER TEXT
// ═══════════════════════════════════════════════════════════════════════════

class GameOverText extends TextComponent with HasGameReference<AsteroidsGame> {
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
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    position = game.size / 2;
  }
}
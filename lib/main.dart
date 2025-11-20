import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asteroids Prototype',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget(
          game: AsteroidsGame(),
        ),
      ),
    );
  }
}

class AsteroidsGame extends FlameGame
    with HasKeyboardHandlerComponents, HasCollisionDetection {
  Spaceship? ship;
  final math.Random _rand = math.Random();

  bool isGameOver = false;
  int level = 1;
  int asteroidCount = 0;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Starfield background
    add(Starfield());

    // Ship
    ship = Spaceship();
    add(ship!);

    // Start level 1 (1 big asteroid)
    startLevel();
  }

  @override
  void onGameResize(Vector2 canvasSize) {
    super.onGameResize(canvasSize);

    // Center the ship if it's already in the game
    if (ship != null && ship!.parent != null) {
      ship!.position = canvasSize / 2;
    }
  }

  void spawnBullet(Vector2 position, double angle) {
    if (isGameOver) return;

    final bullet = Bullet(angle: angle)
      ..position = position
      ..anchor = Anchor.center;
    add(bullet);
  }

  /// Spawn an asteroid of a given size level.
  /// sizeLevel: 2 = large, 1 = medium, 0 = small
  void spawnAsteroid({
    required int sizeLevel,
    Vector2? position,
    Vector2? velocity,
  }) {
    final vel = velocity ??
        Vector2(
          (_rand.nextDouble() - 0.5) * 120, // random X speed
          (_rand.nextDouble() - 0.5) * 120, // random Y speed
        );

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

  /// Create smaller asteroids when a bigger one is destroyed.
  void splitAsteroid(Asteroid parent) {
    final newLevel = parent.sizeLevel - 1;
    if (newLevel < 0) return;

    for (var i = 0; i < 2; i++) {
      final angle = _rand.nextDouble() * 2 * math.pi;
      final speed = 80 + _rand.nextDouble() * 60;
      final vel = Vector2(math.cos(angle), math.sin(angle)) * speed;

      spawnAsteroid(
        sizeLevel: newLevel,
        position: parent.position.clone(),
        velocity: vel,
      );
    }
  }

  /// Called whenever an asteroid is removed from the game (destroyed).
  void onAsteroidDestroyed() {
    if (isGameOver) return;

    asteroidCount--;
    if (asteroidCount <= 0) {
      nextLevel();
    }
  }

  /// Start the current level by spawning [level] big asteroids.
  void startLevel() {
    final center = size / 2;
    final double ringRadius = (math.min(size.x, size.y) * 0.35)
        .clamp(80.0, 400.0)
        .toDouble(); // ensure double

    for (var i = 0; i < level; i++) {
      final angle = (2 * math.pi * i) / level;
      final dir = Vector2(math.cos(angle), math.sin(angle));

      final pos = center + dir * ringRadius;

      // Give them velocities roughly tangent to the circle
      final tangentAngle = angle + math.pi / 2;
      final speed = 60 + _rand.nextDouble() * 80;
      final vel = Vector2(
        math.cos(tangentAngle),
        math.sin(tangentAngle),
      ) * speed;

      spawnAsteroid(
        sizeLevel: 2, // always large at wave start
        position: pos,
        velocity: vel,
      );
    }
  }

  void nextLevel() {
    level++;

    // Reset ship a bit for the new level (only if still alive)
    if (ship != null && ship!.parent != null) {
      ship!
        ..position = size / 2
        ..velocity = Vector2.zero()
        ..angle = 0;
    }

    // Spawn level big asteroids in a ring
    startLevel();
  }

  void gameOver() {
    if (isGameOver) return;
    isGameOver = true;

    // Show GAME OVER text
    add(GameOverText());
  }
}

/// Simple starfield background
class Starfield extends Component with HasGameRef<AsteroidsGame> {
  final List<_Star> _stars = [];
  final int starCount;
  final math.Random _rand = math.Random();

  Starfield({this.starCount = 200}) {
    // Draw behind everything else
    priority = -10;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final size = gameRef.size;

    for (var i = 0; i < starCount; i++) {
      final x = _rand.nextDouble() * size.x;
      final y = _rand.nextDouble() * size.y;

      final radius = 0.5 + _rand.nextDouble() * 2.0; // 0.5 to 2.5
      final brightness = 0.3 + _rand.nextDouble() * 0.7; // 0.3 to 1.0

      final paint = Paint()
        ..color = Colors.white.withOpacity(brightness)
        ..style = PaintingStyle.fill;

      _stars.add(
        _Star(
          position: Offset(x, y),
          radius: radius,
          paint: paint,
        ),
      );
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (final star in _stars) {
      canvas.drawCircle(star.position, star.radius, star.paint);
    }
  }
}

class _Star {
  final Offset position;
  final double radius;
  final Paint paint;

  _Star({
    required this.position,
    required this.radius,
    required this.paint,
  });
}

class Spaceship extends PositionComponent
    with KeyboardHandler, HasGameRef<AsteroidsGame>, CollisionCallbacks {
  final double rotationSpeed = 3.0; // radians per second
  final double thrust = 200.0; // pixels per second^2

  Vector2 velocity = Vector2.zero();

  bool turningLeft = false;
  bool turningRight = false;
  bool accelerating = false;

  Spaceship() : super(size: Vector2(40, 40), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();

    position = gameRef.size / 2;

    // Draw a simple triangle ship
    final shipShape = PolygonComponent.relative(
      [
        Vector2(0.0, -1.0), // nose
        Vector2(0.7, 1.0),  // right rear
        Vector2(-0.7, 1.0), // left rear
      ],
      parentSize: size,
      paint: Paint()..color = Colors.white,
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    add(shipShape);

    // Hitbox for collisions
    add(
      PolygonHitbox.relative(
        [
          Vector2(0.0, -1.0),
          Vector2(0.7, 1.0),
          Vector2(-0.7, 1.0),
        ],
        parentSize: size,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (gameRef.isGameOver) {
      // Freeze ship when game is over
      return;
    }

    // Rotate
    if (turningLeft) {
      angle -= rotationSpeed * dt;
    }
    if (turningRight) {
      angle += rotationSpeed * dt;
    }

    // Thrust in the facing direction
    if (accelerating) {
      final direction = Vector2(0, -1)..rotate(angle);
      velocity += direction * thrust * dt;
    }

    // Move
    position += velocity * dt;

    // Smooth friction when not accelerating
    if (!accelerating) {
      velocity *= 0.95; // tweak for more/less glide

      // Avoid jitter when almost stopped
      if (velocity.length < 1) {
        velocity = Vector2.zero();
      }
    }

    // Screen wrap-around
    final screen = gameRef.size;
    if (position.x < 0) position.x += screen.x;
    if (position.x > screen.x) position.x -= screen.x;
    if (position.y < 0) position.y += screen.y;
    if (position.y > screen.y) position.y -= screen.y;
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (gameRef.isGameOver) {
      // Ignore controls when game is over
      return false;
    }

    turningLeft = keysPressed.contains(LogicalKeyboardKey.arrowLeft);
    turningRight = keysPressed.contains(LogicalKeyboardKey.arrowRight);
    accelerating = keysPressed.contains(LogicalKeyboardKey.arrowUp);

    // Shoot on space bar down
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      final direction = Vector2(0, -1)..rotate(angle);
      final spawnPosition = position + direction * (size.y / 2);
      gameRef.spawnBullet(spawnPosition, angle);
    }

    return true;
  }
}

class Bullet extends CircleComponent
    with CollisionCallbacks, HasGameRef<AsteroidsGame> {
  final double speed = 400.0;
  late final Vector2 velocity;

  Bullet({required double angle})
      : super(
          radius: 3,
          paint: Paint()..color = Colors.yellow,
        ) {
    final dir = Vector2(0, -1)..rotate(angle);
    velocity = dir * speed;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (gameRef.isGameOver) {
      // Freeze bullets on game over
      return;
    }

    position += velocity * dt;

    // Remove bullet when it leaves the screen
    final screen = gameRef.size;
    if (position.x < 0 ||
        position.x > screen.x ||
        position.y < 0 ||
        position.y > screen.y) {
      removeFromParent();
    }
  }
}

class Asteroid extends PositionComponent
    with CollisionCallbacks, HasGameRef<AsteroidsGame> {
  /// 2 = large, 1 = medium, 0 = small
  final int sizeLevel;
  Vector2 velocity;
  final math.Random _rand = math.Random();
  late final List<Vector2> _shapePoints;

  Asteroid({
    required this.sizeLevel,
    required this.velocity,
  }) : super(anchor: Anchor.center);

  static double _sizeForLevel(int level) {
    switch (level) {
      case 2:
        return 60; // large
      case 1:
        return 40; // medium
      default:
        return 24; // small
    }
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final s = _sizeForLevel(sizeLevel);
    size = Vector2(s, s);

    _generateJaggedShape();

    // Visual polygon
    final poly = PolygonComponent.relative(
      _shapePoints,
      parentSize: size,
      paint: Paint()..color = Colors.grey,
    )
      ..anchor = Anchor.center
      ..position = size / 2;

    add(poly);

    // Collision hitbox
    add(
      PolygonHitbox.relative(
        _shapePoints,
        parentSize: size,
      ),
    );
  }

  void _generateJaggedShape() {
    // Create a rough, jagged polygon by randomly varying radius at each angle
    final int vertexCount = 10 + _rand.nextInt(5); // 10–14 points
    _shapePoints = [];

    for (var i = 0; i < vertexCount; i++) {
      final angle = (2 * math.pi * i) / vertexCount;
      final radiusFactor = 0.7 + _rand.nextDouble() * 0.3; // between 0.7 and 1.0

      final x = math.cos(angle) * radiusFactor;
      final y = math.sin(angle) * radiusFactor;

      _shapePoints.add(Vector2(x, y));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (gameRef.isGameOver) {
      // Freeze asteroids on game over
      return;
    }

    // Move asteroid
    position += velocity * dt;

    // Screen wrap-around
    final screen = gameRef.size;
    if (position.x < 0) position.x += screen.x;
    if (position.x > screen.x) position.x -= screen.x;
    if (position.y < 0) position.y += screen.y;
    if (position.y > screen.y) position.y -= screen.y;
  }

  @override
  void onCollision(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    // Bullet hits asteroid -> split or destroy
    if (other is Bullet) {
      other.removeFromParent();

      if (sizeLevel > 0) {
        // Split into two smaller asteroids
        gameRef.splitAsteroid(this);
      }

      // Remove the original asteroid
      removeFromParent();
    }

    // Asteroid hits spaceship -> game over
    if (other is Spaceship) {
      gameRef.gameOver();
      other.removeFromParent();
    }

    super.onCollision(intersectionPoints, other);
  }

  @override
  void onRemove() {
    // Count this asteroid as destroyed (only if not game over)
    gameRef.onAsteroidDestroyed();
    super.onRemove();
  }
}

class GameOverText extends TextComponent with HasGameRef<AsteroidsGame> {
  GameOverText()
      : super(
          text: 'GAME OVER',
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    anchor = Anchor.center;
    position = gameRef.size / 2;
  }
}


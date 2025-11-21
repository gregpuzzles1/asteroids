import 'dart:math' as math;

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
      title: 'Asteroids Game',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget(
          game: AsteroidsGame(),
          focusNode: FocusNode(), // helps ensure keyboard input works
          autofocus: true,
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
  int lives = 3;

  bool get isPlaying => !isGameOver;

  @override
  Color backgroundColor() => Colors.black;

  @override
  Future<void> onLoad() async {
    super.onLoad();

    add(Starfield());
    add(LivesDock());

    ship = Spaceship();
    add(ship!);

    // Auto-start the game immediately
    startLevel();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (ship != null && ship!.parent != null) {
      ship!.position = size / 2;
    }
  }

  void spawnBullet(Vector2 position, double angle) {
    if (!isPlaying) return;

    final bullet = Bullet(angle: angle)
      ..position = position
      ..anchor = Anchor.center;

    add(bullet);
  }

  void spawnAsteroid({
    required int sizeLevel,
    Vector2? position,
    Vector2? velocity,
  }) {
    final vel = velocity ??
        Vector2(
          (_rand.nextDouble() - 0.5) * 120,
          (_rand.nextDouble() - 0.5) * 120,
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

  void onAsteroidDestroyed() {
    if (!isPlaying) return;

    asteroidCount--;

    if (asteroidCount <= 0) {
      nextLevel();
    }
  }

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

  void nextLevel() {
    level++; // B: keep incrementing levels

    if (ship != null && ship!.parent != null) {
      ship!
        ..position = size / 2
        ..velocity = Vector2.zero()
        ..angle = 0;
    }

    startLevel();
  }

  // Called when a ship collides with an asteroid
  void onShipHit(Spaceship hitShip) {
    if (!isPlaying) return;
    if (hitShip.isInvincible) return;

    hitShip.removeFromParent();
    lives--;

    if (lives <= 0) {
      _triggerGameOver();
    } else {
      _respawnShip();
    }
  }

  void _respawnShip() {
    add(
      TimerComponent(
        period: 1.0,
        repeat: false,
        onTick: () {
          final newShip = Spaceship()
            ..position = size / 2
            ..invincibleTime = 2.0; // 2 seconds invincibility
          ship = newShip;
          add(newShip);
        },
      ),
    );
  }

  void _triggerGameOver() {
    isGameOver = true;
    add(GameOverText());
  }
}

//────────────────────────────────────────
// STARFIELD BACKGROUND
//────────────────────────────────────────

class Starfield extends Component with HasGameReference<AsteroidsGame> {
  final int starCount;
  final math.Random _rand = math.Random();

  final List<Offset> _positions = [];
  final List<double> _radii = [];
  final List<Paint> _paints = [];

  Starfield({this.starCount = 200}) {
    priority = -10;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();

    final s = game.size;

    for (var i = 0; i < starCount; i++) {
      final x = _rand.nextDouble() * s.x;
      final y = _rand.nextDouble() * s.y;

      final radius = 0.5 + _rand.nextDouble() * 2.0;
      final brightness = 0.3 + _rand.nextDouble() * 0.7;

      _positions.add(Offset(x, y));
      _radii.add(radius);
      _paints.add(
        Paint()
          ..color = Colors.white.withValues(alpha: brightness)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    for (var i = 0; i < _positions.length; i++) {
      canvas.drawCircle(_positions[i], _radii[i], _paints[i]);
    }
  }
}

//────────────────────────────────────────
// LIVES DOCK (3 ships upper-left)
//────────────────────────────────────────

class LivesDock extends PositionComponent with HasGameReference<AsteroidsGame> {
  LivesDock() : super(position: Vector2(10, 10), size: Vector2(200, 24));

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final lives = game.lives;

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

//────────────────────────────────────────
// SPACESHIP (vector outline)
//────────────────────────────────────────

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

    if (!game.isPlaying) return;

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
    // Blink when invincible
    if (invincibleTime > 0) {
      final t = (invincibleTime * 10).floor();
      if (t.isEven) return;
    }
    super.render(canvas);
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    if (!game.isPlaying) return false;

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

//────────────────────────────────────────
// BULLETS
//────────────────────────────────────────

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

    if (!game.isPlaying) return;

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

//────────────────────────────────────────
// ASTEROIDS
//────────────────────────────────────────

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

    if (!game.isPlaying) return;

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

      if (sizeLevel > 0) {
        game.splitAsteroid(this);
      }

      removeFromParent();
    }

    if (other is Spaceship) {
      game.onShipHit(other);
    }

    super.onCollision(intersectionPoints, other);
  }

  @override
  void onRemove() {
    game.onAsteroidDestroyed();
    super.onRemove();
  }
}

//────────────────────────────────────────
// GAME OVER TEXT
//────────────────────────────────────────

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

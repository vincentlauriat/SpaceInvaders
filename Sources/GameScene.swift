import SpriteKit

final class GameScene: SKScene {

    // MARK: - State

    private enum State {
        case title, playing, playerDying, levelClear, gameOver
    }

    private var state: State = .title
    private var isGamePaused = false

    // MARK: - Tuning

    private let invCols = 11
    private let invRows = 5
    private let invSpacingX: CGFloat = 16
    private let invSpacingY: CGFloat = 16
    private let playerY: CGFloat = 24
    private let playerSpeed: CGFloat = 75
    private let bulletSpeed: CGFloat = 220
    private let ufoY: CGFloat = 222

    // MARK: - Nodes & game data

    private struct Invader {
        let node: SKSpriteNode
        let type: Int   // 0 squid, 1 crab, 2 octopus
        let col: Int
        var alive = true
    }

    private var gameLayer = SKNode()
    private var titleLayer = SKNode()
    private var overlayLayer = SKNode()

    private var invaders: [Invader] = []
    private var aliveCount = 0
    private var invDirection: CGFloat = 1
    private var invFrame = 0
    private var stepTimer: TimeInterval = 0

    private var player: SKSpriteNode!
    private var playerBullet: SKSpriteNode?
    private var alienBullets: [SKSpriteNode] = []
    private var bunkerBlocks: [SKSpriteNode] = []
    private var ufo: SKSpriteNode?
    private var ufoDirection: CGFloat = 1

    private var invTextures: [[SKTexture]] = []
    private var invSizes: [CGSize] = []
    private let rowTypes = [0, 1, 1, 2, 2]  // squid on top, then crabs, then octopi

    private var scoreLabel: BitmapLabel!
    private var hiScoreLabel: BitmapLabel!
    private var livesLabel: BitmapLabel!
    private var lifeIcons: [SKSpriteNode] = []
    private var pausedLabel: BitmapLabel?

    private var score = 0 { didSet { scoreLabel.text = String(format: "%04d", score) } }
    private var hiScore = UserDefaults.standard.integer(forKey: "hiScore")
    private var lives = 3
    private var level = 1
    private var extraLifeAwarded = false

    private var lastUpdate: TimeInterval = 0
    private var stateTimer: TimeInterval = 0
    private var alienFireTimer: TimeInterval = 0
    private var ufoSpawnTimer: TimeInterval = 18
    private var keysDown = Set<UInt16>()

    private let sound = SoundManager.shared

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = .black
        anchorPoint = .zero

        invTextures = [Sprites.squid, Sprites.crab, Sprites.octopus].map { frames in
            frames.map { Pixel.texture($0, color: Palette.white) }
        }
        invSizes = [Sprites.squid, Sprites.crab, Sprites.octopus].map {
            CGSize(width: $0[0][0].count, height: $0[0].count)
        }

        addChild(gameLayer)
        addChild(titleLayer)
        addChild(overlayLayer)
        overlayLayer.zPosition = 900

        buildHUD()
        addChild(Pixel.scanlines(size: size))
        showTitle()
    }

    private func buildHUD() {
        let hud = SKNode()
        hud.zPosition = 50

        let scoreTitle = BitmapLabel("SCORE<1>")
        scoreTitle.position = CGPoint(x: 8, y: 244)
        hud.addChild(scoreTitle)

        let hiTitle = BitmapLabel("HI-SCORE")
        hiTitle.position = CGPoint(x: 88, y: 244)
        hud.addChild(hiTitle)

        scoreLabel = BitmapLabel("0000")
        scoreLabel.position = CGPoint(x: 14, y: 233)
        hud.addChild(scoreLabel)

        hiScoreLabel = BitmapLabel(String(format: "%04d", hiScore))
        hiScoreLabel.position = CGPoint(x: 97, y: 233)
        hud.addChild(hiScoreLabel)

        // Green baseline above the lives area
        var lineData = [UInt8](repeating: 0, count: 224 * 1 * 4)
        for x in 0..<224 {
            let i = x * 4
            lineData[i] = 60; lineData[i + 1] = 255; lineData[i + 2] = 110; lineData[i + 3] = 255
        }
        let line = SKSpriteNode(texture: Pixel.textureFromRGBA(&lineData, width: 224, height: 1))
        line.size = CGSize(width: 224, height: 1)
        line.anchorPoint = .zero
        line.position = CGPoint(x: 0, y: 14)
        hud.addChild(line)

        livesLabel = BitmapLabel("3", color: Palette.green)
        livesLabel.position = CGPoint(x: 8, y: 4)
        hud.addChild(livesLabel)

        addChild(hud)
    }

    private func refreshLivesHUD() {
        livesLabel.text = "\(lives)"
        lifeIcons.forEach { $0.removeFromParent() }
        lifeIcons = []
        for i in 0..<max(0, lives - 1) {
            let icon = Pixel.sprite(Sprites.player, color: Palette.green)
            icon.position = CGPoint(x: 28 + CGFloat(i) * 18, y: 8)
            icon.zPosition = 50
            addChild(icon)
            lifeIcons.append(icon)
        }
    }

    // MARK: - Title screen

    private func showTitle() {
        state = .title
        gameLayer.removeAllChildren()
        titleLayer.removeAllChildren()
        sound.stopUFO()

        func centered(_ text: String, y: CGFloat, color: NSColor = Palette.white, scale: CGFloat = 1) -> BitmapLabel {
            let label = BitmapLabel(text, color: color, anchorX: 0.5)
            label.position = CGPoint(x: 112, y: y)
            label.setScale(scale)
            titleLayer.addChild(label)
            return label
        }

        _ = centered("SPACE", y: 205, color: Palette.green, scale: 2)
        _ = centered("INVADERS", y: 185, color: Palette.green, scale: 2)
        _ = centered("*SCORE ADVANCE TABLE*", y: 152)

        let rows: [(pattern: [String], color: NSColor, text: String)] = [
            (Sprites.ufo, Palette.red, "= ? MYSTERY"),
            (Sprites.squid[0], Palette.white, "= 30 POINTS"),
            (Sprites.crab[0], Palette.white, "= 20 POINTS"),
            (Sprites.octopus[0], Palette.white, "= 10 POINTS"),
        ]
        for (i, row) in rows.enumerated() {
            let y = 132 - CGFloat(i) * 16
            let sprite = Pixel.sprite(row.pattern, color: row.color)
            sprite.position = CGPoint(x: 78, y: y + 4)
            titleLayer.addChild(sprite)
            let label = BitmapLabel(row.text, color: row.color)
            label.position = CGPoint(x: 92, y: y)
            titleLayer.addChild(label)
        }

        let press = centered("PRESS SPACE TO PLAY", y: 44, color: Palette.amber)
        press.run(.repeatForever(.sequence([
            .fadeOut(withDuration: 0.5),
            .fadeIn(withDuration: 0.5),
        ])))
    }

    // MARK: - Game lifecycle

    private func startGame() {
        titleLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        gameLayer.removeAllChildren()

        score = 0
        lives = 3
        level = 1
        extraLifeAwarded = false
        refreshLivesHUD()

        buildPlayer()
        buildWave()
        buildBunkers()
        state = .playing
        ufoSpawnTimer = 18
        alienFireTimer = 1.2
        sound.resetMarch()
    }

    private func buildPlayer() {
        player = Pixel.sprite(Sprites.player, color: Palette.green)
        player.position = CGPoint(x: 20, y: playerY)
        player.zPosition = 10
        gameLayer.addChild(player)
    }

    private func buildWave() {
        invaders = []
        invDirection = 1
        invFrame = 0
        stepTimer = 0

        let topY: CGFloat = 192 - CGFloat(min(level - 1, 5)) * 8
        for row in 0..<invRows {
            let type = rowTypes[row]
            for col in 0..<invCols {
                let node = SKSpriteNode(texture: invTextures[type][0])
                node.size = invSizes[type]
                node.position = CGPoint(
                    x: 24 + CGFloat(col) * invSpacingX,
                    y: topY - CGFloat(row) * invSpacingY
                )
                node.zPosition = 10
                gameLayer.addChild(node)
                invaders.append(Invader(node: node, type: type, col: col))
            }
        }
        aliveCount = invaders.count
    }

    private func buildBunkers() {
        bunkerBlocks.forEach { $0.removeFromParent() }
        bunkerBlocks = []
        let centers: [CGFloat] = [36, 87, 137, 188]
        for cx in centers {
            for (rowI, row) in Sprites.bunkerBlocks.enumerated() {
                for (colI, ch) in Array(row).enumerated() where ch == "#" {
                    let block = SKSpriteNode(color: Palette.green,
                                             size: CGSize(width: 2, height: 2))
                    block.position = CGPoint(
                        x: cx - 11 + CGFloat(colI) * 2 + 1,
                        y: 56 - CGFloat(rowI) * 2 - 1
                    )
                    block.zPosition = 5
                    gameLayer.addChild(block)
                    bunkerBlocks.append(block)
                }
            }
        }
    }

    // MARK: - Input

    override func keyDown(with event: NSEvent) {
        keysDown.insert(event.keyCode)
        guard !event.isARepeat else { return }

        switch event.keyCode {
        case 49:  // space
            switch state {
            case .title, .gameOver:
                startGame()
            case .playing:
                fire()
            default:
                break
            }
        case 35:  // P
            if state == .playing || state == .playerDying {
                togglePause()
            }
        case 46:  // M
            sound.toggleMute()
        case 53:  // esc
            if state != .title { showTitle() }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        keysDown.remove(event.keyCode)
    }

    private func togglePause() {
        isGamePaused.toggle()
        if isGamePaused {
            sound.stopUFO()
            let label = BitmapLabel("PAUSED", color: Palette.amber, anchorX: 0.5)
            label.position = CGPoint(x: 112, y: 128)
            label.setScale(2)
            label.zPosition = 901
            overlayLayer.addChild(label)
            pausedLabel = label
        } else {
            pausedLabel?.removeFromParent()
            pausedLabel = nil
            if ufo != nil { sound.startUFO() }
        }
    }

    private func fire() {
        guard playerBullet == nil else { return }  // one shot on screen, like 1978
        let bullet = Pixel.sprite(Sprites.playerShot, color: Palette.white)
        bullet.position = CGPoint(x: player.position.x, y: playerY + 6)
        bullet.zPosition = 15
        gameLayer.addChild(bullet)
        playerBullet = bullet
        sound.play("shoot")
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : min(currentTime - lastUpdate, 1.0 / 30.0)
        lastUpdate = currentTime
        guard !isGamePaused else { return }

        switch state {
        case .playing:
            updatePlayer(dt)
            updateBullets(dt)
            updateInvaders(dt)
            updateAlienFire(dt)
            updateUFO(dt)
            checkCollisions()
        case .playerDying, .levelClear:
            stateTimer -= dt
            if stateTimer <= 0 { advanceAfterDelay() }
        default:
            break
        }
    }

    private func updatePlayer(_ dt: TimeInterval) {
        var dx: CGFloat = 0
        if keysDown.contains(123) { dx -= 1 }
        if keysDown.contains(124) { dx += 1 }
        player.position.x = min(max(player.position.x + dx * playerSpeed * dt, 10), 214)
    }

    private func updateBullets(_ dt: TimeInterval) {
        if let bullet = playerBullet {
            bullet.position.y += bulletSpeed * dt
            if bullet.position.y > 238 {
                spawnExplosion(at: CGPoint(x: bullet.position.x, y: 236), color: Palette.white)
                bullet.removeFromParent()
                playerBullet = nil
            }
        }
        let alienSpeed: CGFloat = 70 + CGFloat(min(level, 6)) * 6
        for bullet in alienBullets {
            bullet.position.y -= alienSpeed * dt
        }
        alienBullets.removeAll { bullet in
            if bullet.position.y < 16 {
                bullet.removeFromParent()
                return true
            }
            return false
        }
    }

    private var stepInterval: TimeInterval {
        0.045 + Double(aliveCount) * 0.0115
    }

    private func updateInvaders(_ dt: TimeInterval) {
        stepTimer += dt
        guard stepTimer >= stepInterval else { return }
        stepTimer = 0

        let alive = invaders.filter { $0.alive }
        guard !alive.isEmpty else { return }

        let dx = 2 * invDirection
        let minX = alive.map { $0.node.position.x }.min()!
        let maxX = alive.map { $0.node.position.x }.max()!
        let mustDrop = minX + dx < 10 || maxX + dx > 214

        for inv in alive {
            if mustDrop {
                inv.node.position.y -= 8
            } else {
                inv.node.position.x += dx
            }
        }
        if mustDrop {
            invDirection = -invDirection
            // Invaders chew through the bunkers on their way down
            for inv in alive {
                let rect = inv.node.frame.insetBy(dx: -1, dy: -1)
                removeBunkerBlocks { rect.intersects($0.frame) }
            }
            let minY = alive.map { $0.node.position.y }.min()!
            if minY <= playerY + 8 {
                gameOver()
                return
            }
        }

        invFrame ^= 1
        for inv in alive {
            inv.node.texture = invTextures[inv.type][invFrame]
        }
        sound.playMarchStep()
    }

    private func updateAlienFire(_ dt: TimeInterval) {
        alienFireTimer -= dt
        guard alienFireTimer <= 0 else { return }
        alienFireTimer = TimeInterval.random(in: 0.5...1.4) * max(0.4, 1.0 - Double(level) * 0.08)
        guard alienBullets.count < 3 else { return }

        // Shoot from the lowest living invader of a random occupied column
        let columns = Set(invaders.filter { $0.alive }.map { $0.col })
        guard let col = columns.randomElement() else { return }
        let shooter = invaders
            .filter { $0.alive && $0.col == col }
            .min { $0.node.position.y < $1.node.position.y }!

        let bullet = Pixel.sprite(Sprites.alienShot, color: Palette.white)
        bullet.position = CGPoint(x: shooter.node.position.x, y: shooter.node.position.y - 8)
        bullet.zPosition = 15
        gameLayer.addChild(bullet)
        alienBullets.append(bullet)
    }

    private func updateUFO(_ dt: TimeInterval) {
        if let ufo {
            ufo.position.x += ufoDirection * 45 * dt
            if ufo.position.x < -12 || ufo.position.x > 236 {
                ufo.removeFromParent()
                self.ufo = nil
                sound.stopUFO()
            }
        } else {
            ufoSpawnTimer -= dt
            if ufoSpawnTimer <= 0 && aliveCount >= 8 {
                ufoSpawnTimer = TimeInterval.random(in: 18...28)
                let node = Pixel.sprite(Sprites.ufo, color: Palette.red)
                ufoDirection = Bool.random() ? 1 : -1
                node.position = CGPoint(x: ufoDirection > 0 ? -10 : 234, y: ufoY)
                node.zPosition = 10
                gameLayer.addChild(node)
                ufo = node
                sound.startUFO()
            }
        }
    }

    // MARK: - Collisions

    private func checkCollisions() {
        // Player bullet vs invaders / UFO / bunkers
        if let bullet = playerBullet {
            let bframe = bullet.frame
            if let idx = invaders.firstIndex(where: { $0.alive && $0.node.frame.intersects(bframe) }) {
                killInvader(at: idx)
                bullet.removeFromParent()
                playerBullet = nil
            } else if let ufo, ufo.frame.intersects(bframe) {
                killUFO()
                bullet.removeFromParent()
                playerBullet = nil
            } else if hitBunker(at: bullet.position, frame: bframe) {
                bullet.removeFromParent()
                playerBullet = nil
            }
        }

        // Alien bullets vs player / bunkers
        var survivors: [SKSpriteNode] = []
        for bullet in alienBullets {
            let bframe = bullet.frame
            if state == .playing && player.frame.intersects(bframe) {
                bullet.removeFromParent()
                playerHit()
            } else if hitBunker(at: bullet.position, frame: bframe) {
                bullet.removeFromParent()
            } else {
                survivors.append(bullet)
            }
        }
        alienBullets = survivors
    }

    private func killInvader(at idx: Int) {
        invaders[idx].alive = false
        aliveCount -= 1
        let node = invaders[idx].node
        addScore(pointsFor(type: invaders[idx].type))
        spawnExplosion(at: node.position, color: Palette.white)
        node.removeFromParent()
        sound.play("inv_hit")

        if aliveCount == 0 {
            state = .levelClear
            stateTimer = 1.5
            sound.stopUFO()
        }
    }

    private func pointsFor(type: Int) -> Int {
        [30, 20, 10][type]
    }

    private func killUFO() {
        guard let ufo else { return }
        let mystery = [50, 100, 150, 300].randomElement()!
        addScore(mystery)
        sound.stopUFO()
        sound.play("ufo_hit")
        spawnExplosion(at: ufo.position, color: Palette.red)

        let label = BitmapLabel("\(mystery)", color: Palette.red, anchorX: 0.5)
        label.position = ufo.position
        label.zPosition = 20
        gameLayer.addChild(label)
        label.run(.sequence([.wait(forDuration: 0.9), .removeFromParent()]))

        ufo.removeFromParent()
        self.ufo = nil
    }

    private func addScore(_ points: Int) {
        score += points
        if score > hiScore {
            hiScore = score
            hiScoreLabel.text = String(format: "%04d", hiScore)
            UserDefaults.standard.set(hiScore, forKey: "hiScore")
        }
        if !extraLifeAwarded && score >= 1500 {
            extraLifeAwarded = true
            lives += 1
            refreshLivesHUD()
            sound.play("extra")
        }
    }

    private func hitBunker(at point: CGPoint, frame: CGRect) -> Bool {
        guard bunkerBlocks.contains(where: { $0.frame.intersects(frame) }) else { return false }
        removeBunkerBlocks { block in
            let d = hypot(block.position.x - point.x, block.position.y - point.y)
            return d < 3.5 || (d < 6 && Bool.random())
        }
        return true
    }

    private func removeBunkerBlocks(_ shouldRemove: (SKSpriteNode) -> Bool) {
        bunkerBlocks.removeAll { block in
            if shouldRemove(block) {
                block.removeFromParent()
                return true
            }
            return false
        }
    }

    private func spawnExplosion(at point: CGPoint, color: NSColor) {
        let node = Pixel.sprite(Sprites.explosion, color: color)
        node.position = point
        node.zPosition = 20
        gameLayer.addChild(node)
        node.run(.sequence([.wait(forDuration: 0.18), .removeFromParent()]))
    }

    // MARK: - Player death / level / game over

    private func playerHit() {
        lives -= 1
        refreshLivesHUD()
        sound.play("explosion")
        sound.stopUFO()

        let boom = Pixel.sprite(Sprites.playerExplosion, color: Palette.green)
        boom.position = player.position
        boom.zPosition = 20
        boom.name = "playerBoom"
        gameLayer.addChild(boom)
        boom.run(.repeatForever(.sequence([
            .scaleX(to: -1, duration: 0.08),
            .scaleX(to: 1, duration: 0.08),
        ])))
        player.isHidden = true

        state = .playerDying
        stateTimer = 1.2
    }

    private func advanceAfterDelay() {
        switch state {
        case .playerDying:
            gameLayer.childNode(withName: "playerBoom")?.removeFromParent()
            if lives <= 0 {
                gameOver()
            } else {
                player.isHidden = false
                player.position.x = 20
                state = .playing
            }
        case .levelClear:
            level += 1
            playerBullet?.removeFromParent()
            playerBullet = nil
            alienBullets.forEach { $0.removeFromParent() }
            alienBullets = []
            buildWave()
            buildBunkers()
            sound.resetMarch()
            state = .playing
        default:
            break
        }
    }

    private func gameOver() {
        state = .gameOver
        sound.stopUFO()
        sound.play("explosion")

        let label = BitmapLabel("GAME OVER", color: Palette.red, anchorX: 0.5)
        label.position = CGPoint(x: 112, y: 150)
        label.setScale(2)
        label.zPosition = 901
        overlayLayer.addChild(label)

        let press = BitmapLabel("PRESS SPACE TO PLAY", color: Palette.amber, anchorX: 0.5)
        press.position = CGPoint(x: 112, y: 110)
        press.zPosition = 901
        press.alpha = 0
        overlayLayer.addChild(press)
        press.run(.sequence([
            .wait(forDuration: 1.5),
            .repeatForever(.sequence([
                .fadeIn(withDuration: 0.5),
                .fadeOut(withDuration: 0.5),
            ])),
        ]))
    }
}

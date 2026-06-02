package com.example.testmobilegame

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import kotlin.random.Random

/**
 * A simple "catch the falling fruit" game rendered on a SurfaceView.
 *
 * - Drag the basket left/right to catch fruit.
 * - Each catch scores a point and slightly speeds the game up.
 * - Missing a fruit costs a life; the game ends after 3 misses.
 * - Tap after game over to restart.
 */
class GameView(context: Context) : SurfaceView(context), Runnable, SurfaceHolder.Callback {

    private var thread: Thread? = null
    @Volatile private var running = false

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = 56f
    }

    private var viewWidth = 0
    private var viewHeight = 0

    // Basket
    private var basketX = 0f
    private val basketWidth get() = viewWidth * 0.22f
    private val basketHeight get() = viewHeight * 0.04f
    private val basketY get() = viewHeight - basketHeight * 3f

    // Falling fruit
    private var fruitX = 0f
    private var fruitY = 0f
    private val fruitRadius get() = viewWidth * 0.045f
    private var fruitSpeed = 0f
    private var fruitColor = Color.RED

    private var score = 0
    private var lives = 3
    private var gameOver = false
    private var initialized = false

    private val fruitColors = intArrayOf(
        Color.rgb(229, 57, 53),
        Color.rgb(255, 179, 0),
        Color.rgb(67, 160, 71),
        Color.rgb(142, 36, 170),
        Color.rgb(255, 112, 67)
    )

    init {
        holder.addCallback(this)
        isFocusable = true
    }

    private fun resetGame() {
        score = 0
        lives = 3
        gameOver = false
        fruitSpeed = viewHeight * 0.012f
        basketX = viewWidth / 2f
        spawnFruit()
        initialized = true
    }

    private fun spawnFruit() {
        fruitX = Random.nextFloat() * (viewWidth - 2 * fruitRadius) + fruitRadius
        fruitY = -fruitRadius
        fruitColor = fruitColors[Random.nextInt(fruitColors.size)]
    }

    private fun update() {
        if (gameOver || !initialized) return

        fruitY += fruitSpeed

        val basketTop = basketY
        val basketLeft = basketX - basketWidth / 2f
        val basketRight = basketX + basketWidth / 2f

        // Catch detection
        if (fruitY + fruitRadius >= basketTop &&
            fruitY - fruitRadius <= basketTop + basketHeight &&
            fruitX >= basketLeft && fruitX <= basketRight
        ) {
            score++
            fruitSpeed += viewHeight * 0.0004f
            spawnFruit()
        } else if (fruitY - fruitRadius > viewHeight) {
            // Missed
            lives--
            if (lives <= 0) {
                gameOver = true
            } else {
                spawnFruit()
            }
        }
    }

    private fun drawGame(canvas: Canvas) {
        // Background
        canvas.drawColor(Color.rgb(13, 71, 161))

        if (!initialized) return

        // Basket
        paint.color = Color.rgb(141, 110, 99)
        val basketRect = RectF(
            basketX - basketWidth / 2f,
            basketY,
            basketX + basketWidth / 2f,
            basketY + basketHeight
        )
        canvas.drawRoundRect(basketRect, 18f, 18f, paint)
        paint.color = Color.rgb(93, 64, 55)
        canvas.drawRect(
            basketX - basketWidth / 2f,
            basketY,
            basketX + basketWidth / 2f,
            basketY + basketHeight * 0.35f,
            paint
        )

        // Fruit
        paint.color = fruitColor
        canvas.drawCircle(fruitX, fruitY, fruitRadius, paint)
        paint.color = Color.rgb(56, 142, 60)
        canvas.drawRect(
            fruitX - 3f,
            fruitY - fruitRadius - 14f,
            fruitX + 3f,
            fruitY - fruitRadius,
            paint
        )

        // HUD
        canvas.drawText("Score: $score", 40f, 80f, textPaint)
        canvas.drawText("Lives: $lives", viewWidth - 260f, 80f, textPaint)

        if (gameOver) {
            paint.color = Color.argb(180, 0, 0, 0)
            canvas.drawRect(0f, 0f, viewWidth.toFloat(), viewHeight.toFloat(), paint)
            val big = Paint(textPaint).apply { textSize = 96f }
            drawCentered(canvas, "GAME OVER", viewHeight / 2f - 60f, big)
            drawCentered(canvas, "Score: $score", viewHeight / 2f + 40f, textPaint)
            drawCentered(canvas, "Tap to play again", viewHeight / 2f + 130f, textPaint)
        }
    }

    private fun drawCentered(canvas: Canvas, text: String, y: Float, p: Paint) {
        val w = p.measureText(text)
        canvas.drawText(text, (viewWidth - w) / 2f, y, p)
    }

    override fun run() {
        while (running) {
            val holder = holder
            if (!holder.surface.isValid) continue
            update()
            val canvas = holder.lockCanvas() ?: continue
            try {
                drawGame(canvas)
            } finally {
                holder.unlockCanvasAndPost(canvas)
            }
            try {
                Thread.sleep(16) // ~60 FPS
            } catch (_: InterruptedException) {
            }
        }
    }

    fun resume() {
        if (running) return
        running = true
        thread = Thread(this).also { it.start() }
    }

    fun pause() {
        running = false
        try {
            thread?.join()
        } catch (_: InterruptedException) {
        }
        thread = null
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                if (gameOver) {
                    if (event.action == MotionEvent.ACTION_DOWN) resetGame()
                } else {
                    basketX = event.x.coerceIn(basketWidth / 2f, viewWidth - basketWidth / 2f)
                }
            }
        }
        return true
    }

    override fun surfaceCreated(holder: SurfaceHolder) {}

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        viewWidth = width
        viewHeight = height
        if (!initialized) resetGame()
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {}
}

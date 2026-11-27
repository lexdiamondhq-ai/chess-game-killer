package com.chessgamekiller.chess

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PositionTest {
    private fun perft(p: Position, depth: Int): Long {
        if (depth == 0) return 1
        val moves = p.legalMoves()
        if (depth == 1) return moves.size.toLong()
        return moves.sumOf { perft(p.play(it), depth - 1) }
    }

    @Test fun startPerft() {
        val p = Position.start()
        assertEquals(20, perft(p, 1))
        assertEquals(400, perft(p, 2))
        assertEquals(8902, perft(p, 3))
        assertEquals(197281, perft(p, 4))
    }

    @Test fun kiwipetePerft() {
        val p = Position.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")!!
        assertEquals(48, perft(p, 1))
        assertEquals(2039, perft(p, 2))
        assertEquals(97862, perft(p, 3))
    }

    @Test fun position3Perft() {
        val p = Position.fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")!!
        assertEquals(14, perft(p, 1))
        assertEquals(191, perft(p, 2))
        assertEquals(2812, perft(p, 3))
        assertEquals(43238, perft(p, 4))
    }

    @Test fun position4Perft() {
        val p = Position.fromFen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1")!!
        assertEquals(6, perft(p, 1))
        assertEquals(264, perft(p, 2))
        assertEquals(9467, perft(p, 3))
    }

    @Test fun position5Perft() {
        val p = Position.fromFen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")!!
        assertEquals(44, perft(p, 1))
        assertEquals(1486, perft(p, 2))
        assertEquals(62379, perft(p, 3))
    }

    @Test fun fenRoundTrip() {
        val fen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5"
        assertEquals(fen, Position.fromFen(fen)!!.fen)
        assertEquals(Position.START_FEN, Position.start().fen)
    }

    @Test fun badFens() {
        assertNull(Position.fromFen("8/8/8/8/8/8/8/8 w - - 0 1"))
        assertNull(Position.fromFen("hello"))
        // Side not to move in check
        assertNull(Position.fromFen("4k3/8/8/8/8/8/4Q3/4K3 w - - 0 1"))
    }

    @Test fun san() {
        val p = Position.fromFen("r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 1 5")!!
        assertEquals("O-O", p.san(Move.fromUci("e1g1")!!))
        assertEquals("Ng5", p.san(Move.fromUci("f3g5")!!))
        assertEquals("Bxf7+", p.san(Move.fromUci("c4f7")!!))
        val knights = Position.fromFen("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")!!
        assertEquals("Nbd2", knights.san(Move.fromUci("b1d2")!!))
        val promo = Position.fromFen("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1")!!
        assertEquals("b8=Q+", promo.san(Move.fromUci("b7b8q")!!))
        assertEquals("b8=N", promo.san(Move.fromUci("b7b8n")!!))
        assertNotNull(p.parseSan("Bxf7+"))
    }

    @Test fun gameEnds() {
        val g = Game()
        for (m in listOf("f2f3", "e7e5", "g2g4", "d8h4")) assertNotNull(g.playUci(m))
        assertEquals(GameStatus.CHECKMATE, g.status)
        assertEquals(false, g.whiteWon)
        assertEquals("1. f3 e5 2. g4 Qh4#", g.pgnMoves())

        val r = Game()
        repeat(2) { for (m in listOf("g1f3", "g8f6", "f3g1", "f6g8")) r.playUci(m) }
        assertEquals(GameStatus.REPETITION, r.status)

        val stale = Position.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!!
        assertEquals(GameStatus.STALEMATE, Game(stale).status)
        assertTrue(Position.fromFen("4k3/8/8/8/8/8/8/4KB2 w - - 0 1")!!.insufficientMaterial)
    }

    @Test fun nullMove() {
        val p = Position.start()
        val n = p.nullMove()!!
        assertEquals(false, n.whiteToMove)
    }
}

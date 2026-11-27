package com.chessgamekiller.app

import com.chessgamekiller.app.analyze.Scanner
import com.chessgamekiller.app.engine.Stockfish
import com.chessgamekiller.chess.Position
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsingTest {
    @Test fun readsEngineLines() {
        val (index, line) = Stockfish.parseInfo(
            "info depth 12 seldepth 18 multipv 2 score cp -31 nodes 100 nps 1 hashfull 0 tbhits 0 time 3 pv e7e5 g1f3 b8c6",
        )!!
        assertEquals(2, index)
        assertEquals(-31, line.eval.cp)
        assertEquals(listOf("e7e5", "g1f3", "b8c6"), line.moves)
        val mate = Stockfish.parseInfo("info depth 5 multipv 1 score mate -2 pv d8h4")!!.second
        assertEquals(-2, mate.eval.mate)
        assertEquals(null, Stockfish.parseInfo("info depth 5 currmove e2e4 currmovenumber 1"))
        assertEquals(null, Stockfish.parseInfo("info depth 9 multipv 1 score cp 20 lowerbound pv e2e4"))
    }

    @Test fun readsAPhotoWithWhiteAtTheBottom() {
        val body = """{"found":true,"rows":["rnbqkbnr","pppppppp","........","........","....P...","........","PPPP.PPP","RNBQKBNR"],"white_side":"bottom","side_to_move":"black","confidence":"high"}"""
        val r = Scanner.parse(body)
        assertFalse(r.whiteToMove)
        assertTrue(r.sureOfTurn)
        val p = Position.fromCells(r.cells, r.whiteToMove)
        assertNotNull(p)
        assertEquals("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", p!!.fen)
    }

    @Test fun readsAPhotoWithWhiteAtTheTop() {
        // The start position photographed from Black's side.
        val body = """{"found":true,"rows":["RNBKQBNR","PPPPPPPP","........","........","........","........","pppppppp","rnbkqbnr"],"white_side":"top","side_to_move":null,"confidence":"high"}"""
        val r = Scanner.parse(body)
        assertTrue(r.whiteToMove)
        assertFalse(r.sureOfTurn)
        assertEquals(Position.START_FEN, Position.fromCells(r.cells, true)!!.fen)
    }
}

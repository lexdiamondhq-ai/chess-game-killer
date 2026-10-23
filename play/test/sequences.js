// Long move sequences for the unit tests, found by a seeded random search
// with chess.js and checked to end the game only on their last move.

/** 100 half-moves of piece moves with no capture, no pawn move and no position three times: the fifty-move rule. */
export const FIFTY_MOVES =
  "b1c3 b8c6 c3a4 g8f6 a1b1 f6h5 b1a1 c6a5 g1f3 a5c6 h1g1 h5g3 a1b1 c6b4 a4c3 b4a6 b1a1 g3h1 a1b1 h8g8 " +
  "f3g5 g8h8 c3b5 h1g3 g5e4 g3f5 e4c3 f5d6 b5d4 d6c4 g1h1 a8b8 d4c6 a6b4 b1a1 b8a8 c3b1 c4a3 c6a5 b4d5 " +
  "a5c6 h8g8 b1c3 a3b5 c3a4 d5b4 c6d4 b4d5 a4c3 b5a3 d4b5 a3b1 b5d4 d5b6 d4f5 b6c4 c3d5 c4d6 d5c3 d6c4 " +
  "h1g1 a8b8 c3b5 c4b6 f5d4 b6c4 d4c6 c4b6 g1h1 b6d5 c6d4 d5f4 h1g1 f4h5 g1h1 h5f4 b5a3 g8h8 d4f5 f4h5 " +
  "h1g1 h5f6 a3c4 f6h5 c4e3 h5f6 g1h1 b1c3 f5h6 c3a4 e3g4 a4c5 h6f5 b8a8 a1b1 c5a4 f5g3 a4b6 g3e4 h8g8";

/** Captures down to bare kings: the last move leaves nobody able to mate. */
export const INSUFFICIENT =
  "b1a3 c7c6 f2f4 g7g5 f4g5 f8g7 h2h3 g7b2 c1b2 g8f6 g5f6 e7f6 b2f6 d8f6 h3h4 f6h4 h1h4 d7d6 h4h7 h8h7 " +
  "d1c1 b7b5 a3b5 c6b5 g1h3 h7h3 g2h3 c8h3 f1h3 f7f6 a2a3 e8e7 e1d1 b8d7 h3d7 a8g8 d7b5 f6f5 b5a6 e7d8 " +
  "c1b2 d8e7 d1c1 g8b8 b2b8 f5f4 b8d6 e7d6 c2c4 d6e5 c1c2 e5f5 e2e3 f5e6 e3f4 e6f5 a6b5 f5f4 b5d7 a7a5 " +
  "d7g4 f4g4 c2b3 g4g3 a1g1 g3h3 g1g2 h3g2 a3a4 g2h2 d2d3 h2g3 b3c3 g3g2 c4c5 g2h3 c3c2 h3h4 c5c6 h4g5 " +
  "c2b1 g5f4 c6c7 f4g4 c7c8r g4f5 d3d4 f5g4 c8c4 g4h4 d4d5 h4g3 c4c6 g3f2 c6b6 f2g2 b6a6 g2f3 a6a5 f3e3 " +
  "b1c1 e3e2 c1b1 e2f1 d5d6 f1e1 a5a7 e1e2 b1c2 e2e1 a7a8 e1f2 c2c3 f2g1 a8a7 g1h1 c3d2 h1g2 d2c1 g2h3 " +
  "a7e7 h3g3 d6d7 g3h3 c1d1 h3g3 d7d8r g3f4 e7e6 f4g3 e6e3 g3g4 d8d5 g4h4 d1c1 h4g4 e3f3 g4f3 d5e5 f3f2 " +
  "e5f5 f2g2 f5f6 g2h1 c1d1 h1g1 f6c6 g1f2 a4a5 f2e3 c6h6 e3f4 h6h1 f4e5 d1c1 e5f6 h1h3 f6f7 h3h2 f7f6 " +
  "h2e2 f6f7 a5a6 f7f8 e2f2 f8g7 f2d2 g7g8 d2g2 g8f7 g2d2 f7f6 d2d3 f6e7 d3e3 e7d8 e3e6 d8c7 e6f6 c7d7 " +
  "f6f8 d7e7 f8g8 e7f6 g8g2 f6f7 g2c2 f7g7 c2c5 g7h7 c5c4 h7g8 a6a7 g8g7 c4c5 g7h6 c1b1 h6g7 b1c2 g7f6 " +
  "c2d3 f6g7 d3e4 g7f6 c5b5 f6e7 e4e3 e7f7 b5b6 f7f8 e3d4 f8e7 b6b5 e7f7 b5b4 f7f8 b4a4 f8f7 a7a8q f7e7 " +
  "a8d5 e7f6 d5a8 f6g6 a4a7 g6f5 a7c7 f5g5 a8a7 g5f4 a7a4 f4g5 c7h7 g5f4 d4c3 f4g3 h7g7 g3h3 a4d1 h3h4 " +
  "d1h5 h4h5 c3b2 h5h4 b2b3 h4h5 b3c2 h5h6 g7g8 h6h5 c2b1 h5h4 g8f8 h4h5 f8b8 h5g5 b8g8 g5h6 g8f8 h6h7 " +
  "f8c8 h7g6 c8c1 g6f6 c1c7 f6g5 c7a7 g5f4 a7f7 f4g5 f7f5 g5f5";

/** Black is down to a lone king and White, to move, still has a rook: White's flag falling is a draw. */
export const LONE_BLACK_KING =
  "b1a3 c7c6 f2f4 g7g5 f4g5 f8g7 h2h3 g7b2 c1b2 g8f6 g5f6 e7f6 b2f6 d8f6 h3h4 f6h4 h1h4 d7d6 h4h7 h8h7 " +
  "d1c1 b7b5 a3b5 c6b5 g1h3 h7h3 g2h3 c8h3 f1h3 f7f6 a2a3 e8e7 e1d1 b8d7 h3d7 a8g8 d7b5 f6f5 b5a6 e7d8 " +
  "c1b2 d8e7 d1c1 g8b8 b2b8 f5f4 b8d6 e7d6 c2c4 d6e5 c1c2 e5f5 e2e3 f5e6 e3f4 e6f5 a6b5 f5f4 b5d7 a7a5 " +
  "d7g4 f4g4 c2b3 g4g3 a1g1 g3h3 g1g2 h3g2 a3a4 g2h2 d2d3 h2g3 b3c3 g3g2 c4c5 g2h3 c3c2 h3h4 c5c6 h4g5 " +
  "c2b1 g5f4 c6c7 f4g4 c7c8r g4f5 d3d4 f5g4 c8c4 g4h4 d4d5 h4g3 c4c6 g3f2 c6b6 f2g2 b6a6 g2f3 a6a5 f3e3";

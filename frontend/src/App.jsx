import { useEffect, useState, useRef } from "react";
import axios from "axios";
import "./index.css";

const API = "";

export default function Game2048() {
  const [gameId, setGameId] = useState(null);
  const [board, setBoard] = useState([]);
  const [score, setScore] = useState(0);
  const [bestScore, setBestScore] = useState(() => {
    return parseInt(localStorage.getItem('2048-best-score') || '0');
  });
  const [gameOver, setGameOver] = useState(false);
  const [won, setWon] = useState(false);
  const [lastBoard, setLastBoard] = useState([]);
  const [error, setError] = useState(null);
  const [newTiles, setNewTiles] = useState([]);
  const [loading, setLoading] = useState(false);
  const [isMoving, setIsMoving] = useState(false);
  const [isDarkMode, setIsDarkMode] = useState(() => {
    return localStorage.getItem('2048-theme') === 'dark';
  });
  const [showMenu, setShowMenu] = useState(false);
  const [showHowToPlay, setShowHowToPlay] = useState(false);
  const [showLeaderboard, setShowLeaderboard] = useState(false);
  const [showSubmitScore, setShowSubmitScore] = useState(false);
  const [leaderboardData, setLeaderboardData] = useState([]);
  const [playerName, setPlayerName] = useState(() => {
    return localStorage.getItem('2048-player-name') || '';
  });
  const [gameStartTime, setGameStartTime] = useState(null);
  const [moveCount, setMoveCount] = useState(0);
  
  // Use refs to store current values for event handlers
  const gameIdRef = useRef(null);
  const gameOverRef = useRef(false);
  const loadingRef = useRef(false);
  const boardRef = useRef([]);

  useEffect(() => {
    startNewGame();
    // Apply theme to document
    document.documentElement.classList.toggle('dark', isDarkMode);
  }, []);

  useEffect(() => {
    // Update best score
    if (score > bestScore) {
      setBestScore(score);
      localStorage.setItem('2048-best-score', score.toString());
    }
  }, [score, bestScore]);

  const toggleTheme = () => {
    const newTheme = !isDarkMode;
    setIsDarkMode(newTheme);
    localStorage.setItem('2048-theme', newTheme ? 'dark' : 'light');
    document.documentElement.classList.toggle('dark', newTheme);
  };

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.key)) {
        e.preventDefault();
        const dir = e.key.replace("Arrow", "").toLowerCase();
        handleMove(dir);
      }
    };

    // Touch/swipe support
    let touchStartX = 0;
    let touchStartY = 0;
    
    const handleTouchStart = (e) => {
      touchStartX = e.touches[0].clientX;
      touchStartY = e.touches[0].clientY;
    };
    
    const handleTouchEnd = (e) => {
      if (!touchStartX || !touchStartY) return;
      
      const touchEndX = e.changedTouches[0].clientX;
      const touchEndY = e.changedTouches[0].clientY;
      
      const diffX = touchStartX - touchEndX;
      const diffY = touchStartY - touchEndY;
      
      const minSwipeDistance = 50;
      
      if (Math.abs(diffX) > Math.abs(diffY)) {
        // Horizontal swipe
        if (Math.abs(diffX) > minSwipeDistance) {
          handleMove(diffX > 0 ? 'left' : 'right');
        }
      } else {
        // Vertical swipe
        if (Math.abs(diffY) > minSwipeDistance) {
          handleMove(diffY > 0 ? 'up' : 'down');
        }
      }
      
      touchStartX = 0;
      touchStartY = 0;
    };

    window.addEventListener("keydown", handleKeyDown);
    window.addEventListener("touchstart", handleTouchStart);
    window.addEventListener("touchend", handleTouchEnd);
    
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      window.removeEventListener("touchstart", handleTouchStart);
      window.removeEventListener("touchend", handleTouchEnd);
    };
  }, []);

  const startNewGame = async () => {
    try {
      setLoading(true);
      setError(null);
      console.log('Starting new game...');
      const res = await axios.post(`${API}/game/new`);
      console.log('New game response:', res.data);
      setGameId(res.data.id);
      gameIdRef.current = res.data.id;
      setBoard(res.data.board);
      boardRef.current = res.data.board;
      setLastBoard(res.data.board);
      setScore(res.data.score);
      setGameOver(false);
      gameOverRef.current = false;
      setWon(false);
      setNewTiles([]);
      setGameStartTime(Date.now());
      setMoveCount(0);
    } catch (err) {
      console.error('Error creating new game:', err);
      setError("Error creating new game.");
    } finally {
      setLoading(false);
      loadingRef.current = false;
    }
  };

  // Leaderboard functions
  const fetchLeaderboard = async () => {
    try {
      const res = await axios.get(`${API}/leaderboard/top?limit=10`);
      setLeaderboardData(res.data.scores || []);
    } catch (err) {
      console.error("Error fetching leaderboard:", err);
    }
  };

  const submitScore = async () => {
    if (!playerName.trim() || score === 0) return;

    const duration = gameStartTime ? Math.floor((Date.now() - gameStartTime) / 1000) : 0;
    const playerId = localStorage.getItem('2048-player-id') || generatePlayerId();
    
    if (!localStorage.getItem('2048-player-id')) {
      localStorage.setItem('2048-player-id', playerId);
    }

    try {
      await axios.post(`${API}/leaderboard/submit`, {
        playerId,
        name: playerName.trim(),
        score,
        duration,
        moves: moveCount
      });
      
      localStorage.setItem('2048-player-name', playerName.trim());
      setShowSubmitScore(false);
      setShowLeaderboard(true);
      fetchLeaderboard();
    } catch (err) {
      setError("Error submitting score.");
    }
  };

  const generatePlayerId = () => {
    return 'player_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
  };

  const handleMove = async (dir) => {
    if (!gameIdRef.current || gameOverRef.current || loadingRef.current || isMoving) {
      console.log('Move blocked:', { gameId: gameIdRef.current, gameOver: gameOverRef.current, loading: loadingRef.current, isMoving });
      return;
    }
    
    try {
      setIsMoving(true);
      setError(null);
      console.log('Making move:', dir, 'for game:', gameIdRef.current);
      
      const res = await axios.post(`${API}/game/move`, { id: gameIdRef.current, direction: dir });
      
      setLastBoard(boardRef.current);
      setBoard(res.data.board);
      boardRef.current = res.data.board;
      setScore(res.data.score);
      setGameOver(res.data.gameOver);
      gameOverRef.current = res.data.gameOver;
      setWon(res.data.won);

      // Find only truly new tiles (spawned after move)
      const newTilesArr = [];
      const oldFlat = boardRef.current.flat();
      const newFlat = res.data.board.flat();
      
      res.data.board.forEach((row, r) => {
        row.forEach((cell, c) => {
          const index = r * 4 + c;
          if (cell !== 0 && oldFlat[index] === 0) {
            newTilesArr.push(`${r}-${c}`);
          }
        });
      });
      
      setNewTiles(newTilesArr);
      setTimeout(() => setNewTiles([]), 200);
      
      // Increment move count
      setMoveCount(prev => prev + 1);
      
      // Check if game ended and show submit score option
      console.log('Game response:', { gameOver: res.data.gameOver, score: res.data.score, currentScore: score });
      console.log('Game over check:', res.data.gameOver, 'Score check:', res.data.score > 0, 'Full response:', res.data);
      if (res.data.gameOver && res.data.score > 0) {
        console.log('Game over detected, showing submit score dialog');
        setTimeout(() => setShowSubmitScore(true), 1000);
      } else {
        console.log('Game over not detected - gameOver:', res.data.gameOver, 'score:', res.data.score);
      }
    } catch (err) {
      console.error('Error making move:', err);
      setError("Error making move.");
    } finally {
      setTimeout(() => setIsMoving(false), 150);
    }
  };

  return (
    <div className={`game-container ${isDarkMode ? 'dark' : ''}`}>
      <div className="game-wrapper">
        {/* Header */}
        <div className="header">
          <div className="title-section">
            <h1 className="game-title">2048</h1>
            <p className="game-subtitle">Join the tiles, get to 2048!</p>
          </div>
          <div className="header-buttons">
            <button
              onClick={() => setShowMenu(true)}
              className="menu-button"
              aria-label="Open menu"
            >
              ☰
            </button>
            <button
              onClick={toggleTheme}
              className="theme-toggle"
              aria-label="Toggle theme"
            >
              {isDarkMode ? '☀️' : '🌙'}
            </button>
          </div>
        </div>

        {/* Score Section */}
        <div className="score-section">
          <div className={`score-box ${isDarkMode ? 'dark' : ''}`}>
            <div className="score-label">SCORE</div>
            <div className="score-value">{score.toLocaleString()}</div>
          </div>
          <div className={`score-box ${isDarkMode ? 'dark' : ''}`}>
            <div className="score-label">BEST</div>
            <div className="score-value">{bestScore.toLocaleString()}</div>
          </div>
        </div>

        {/* Game Status */}
        <div className="status-section">
          {won && !gameOver && (
            <div className={`status-message success ${isDarkMode ? 'dark' : ''}`}>
              🎉 You Won! Keep playing to reach higher scores!
            </div>
          )}
          {gameOver && (
            <div className={`status-message game-over ${isDarkMode ? 'dark' : ''}`}>
              Game Over! Final Score: {score.toLocaleString()}
            </div>
          )}
          {loading && (
            <div className={`status-message loading ${isDarkMode ? 'dark' : ''}`}>
              Loading...
            </div>
          )}
          {error && (
            <div className={`status-message error ${isDarkMode ? 'dark' : ''}`}>
              {error}
            </div>
          )}
        </div>

        {/* Game Board */}
        <div className={`game-board ${isDarkMode ? 'dark' : ''} ${isMoving ? 'moving' : ''}`}>
          {Array.isArray(board) && board.length > 0 ? (
            board.flat().map((cell, i) => {
              const value = cell !== 0 ? cell : "";
              const r = Math.floor(i / 4);
              const c = i % 4;
              const isNew = newTiles.includes(`${r}-${c}`);
              
              return (
                <div
                  key={i}
                  className={`game-tile tile-${cell} ${isNew ? "tile-new" : ""} ${isDarkMode ? 'dark' : ''}`}
                  role="gridcell"
                  aria-label={value || "empty"}
                >
                  {value}
                </div>
              );
            })
          ) : (
            Array.from({ length: 16 }, (_, i) => (
              <div
                key={`fallback-${i}`}
                className={`game-tile tile-0 ${isDarkMode ? 'dark' : ''}`}
                role="gridcell"
                aria-label="empty"
              />
            ))
          )}
        </div>

        {/* Controls */}
        <div className="controls-section">
          <button
            onClick={startNewGame}
            disabled={loading}
            className={`new-game-btn ${isDarkMode ? 'dark' : ''} ${loading ? 'loading' : ''}`}
          >
            {loading ? "Starting..." : "New Game"}
          </button>
        </div>
      </div>

      {/* Menu Modal */}
      {showMenu && (
        <div className="modal-overlay" onClick={() => setShowMenu(false)}>
          <div className={`modal ${isDarkMode ? 'dark' : ''}`} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>Menu</h2>
              <button onClick={() => setShowMenu(false)} className="close-btn">×</button>
            </div>
            <div className="modal-content">
              <button 
                className="menu-item"
                onClick={() => {
                  setShowMenu(false);
                }}
                disabled={!gameId || gameOver}
              >
                Keep Going
              </button>
              <button 
                className="menu-item"
                onClick={() => {
                  setShowMenu(false);
                  startNewGame();
                }}
              >
                New Game
              </button>
              <button 
                className="menu-item"
                onClick={() => {
                  setShowMenu(false);
                  setShowLeaderboard(true);
                  fetchLeaderboard();
                }}
              >
                Leaderboard
              </button>
              <button 
                className="menu-item"
                onClick={() => {
                  setShowMenu(false);
                  setShowHowToPlay(true);
                }}
              >
                How to Play
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Leaderboard Modal */}
      {showLeaderboard && (
        <div className="modal-overlay" onClick={() => setShowLeaderboard(false)}>
          <div className={`modal ${isDarkMode ? 'dark' : ''}`} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>🏆 Leaderboard</h2>
              <button onClick={() => setShowLeaderboard(false)} className="close-btn">×</button>
            </div>
            <div className="modal-content">
              <div className="leaderboard">
                {leaderboardData.length > 0 ? (
                  <div className="leaderboard-list">
                    {leaderboardData.map((entry, index) => (
                      <div key={entry.id} className={`leaderboard-entry ${index < 3 ? 'top-three' : ''}`}>
                        <div className="rank">
                          {index === 0 && '🥇'}
                          {index === 1 && '🥈'}
                          {index === 2 && '🥉'}
                          {index > 2 && `#${index + 1}`}
                        </div>
                        <div className="player-info">
                          <div className="player-name">{entry.name}</div>
                          <div className="player-stats">
                            {entry.moves} moves • {Math.floor(entry.duration / 60)}:{(entry.duration % 60).toString().padStart(2, '0')}
                          </div>
                        </div>
                        <div className="player-score">{entry.score.toLocaleString()}</div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="empty-leaderboard">
                    <p>No scores yet! Be the first to submit a score.</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Submit Score Modal */}
      {showSubmitScore && (
        <div className="modal-overlay" onClick={() => setShowSubmitScore(false)}>
          <div className={`modal ${isDarkMode ? 'dark' : ''}`} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>🎉 Submit Your Score</h2>
              <button onClick={() => setShowSubmitScore(false)} className="close-btn">×</button>
            </div>
            <div className="modal-content">
              <div className="submit-score">
                <div className="score-summary">
                  <div className="final-score">
                    <span className="label">Final Score:</span>
                    <span className="value">{score.toLocaleString()}</span>
                  </div>
                  <div className="game-stats">
                    <span>Moves: {moveCount}</span>
                    <span>Time: {gameStartTime ? Math.floor((Date.now() - gameStartTime) / 1000 / 60) : 0}:{gameStartTime ? ((Math.floor((Date.now() - gameStartTime) / 1000)) % 60).toString().padStart(2, '0') : '00'}</span>
                  </div>
                </div>
                <div className="name-input">
                  <label htmlFor="playerName">Your Name:</label>
                  <input
                    id="playerName"
                    type="text"
                    value={playerName}
                    onChange={(e) => setPlayerName(e.target.value)}
                    placeholder="Enter your name"
                    maxLength={20}
                    className={`name-field ${isDarkMode ? 'dark' : ''}`}
                  />
                </div>
                <div className="submit-actions">
                  <button
                    onClick={submitScore}
                    disabled={!playerName.trim()}
                    className={`submit-btn ${isDarkMode ? 'dark' : ''}`}
                  >
                    Submit Score
                  </button>
                  <button
                    onClick={() => setShowSubmitScore(false)}
                    className={`skip-btn ${isDarkMode ? 'dark' : ''}`}
                  >
                    Skip
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* How to Play Modal */}
      {showHowToPlay && (
        <div className="modal-overlay" onClick={() => setShowHowToPlay(false)}>
          <div className={`modal ${isDarkMode ? 'dark' : ''}`} onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>How to Play</h2>
              <button onClick={() => setShowHowToPlay(false)} className="close-btn">×</button>
            </div>
            <div className="modal-content">
              <div className="how-to-play">
                <div className="rule">
                  <strong>🎯 GOAL:</strong>
                  <p>Reach the 2048 tile to win!</p>
                </div>
                <div className="rule">
                  <strong>🎮 CONTROLS:</strong>
                  <p>Use your arrow keys to move the tiles</p>
                  <p className="mobile-only">On mobile: Swipe to move tiles</p>
                </div>
                <div className="rule">
                  <strong>🔄 MERGING:</strong>
                  <p>When two tiles with the same number touch, they merge into one!</p>
                </div>
                <div className="rule">
                  <strong>📈 SCORING:</strong>
                  <p>Every time you merge tiles, you get points equal to the new tile's value</p>
                </div>
                <div className="rule">
                  <strong>🏁 GAME OVER:</strong>
                  <p>The game ends when you can't make any more moves</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
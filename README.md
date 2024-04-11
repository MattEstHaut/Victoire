# Victoire ⚔️

**Victoire** is a [UCI](https://github.com/nomemory/uci-protocol-specification) chess engine written in [Zig](https://ziglang.org/). It uses **pruning** and **reduction** techniques to reduce the search space of the **principal variation search** (**PVS**). And several other methods to accelerate the search or enhance evaluation, such as the use of **transposition tables**, **quiescence search**, **tapered evaluation**...

## ⚡️ Quick start

First, download and install **Zig** from the [official website](https://ziglang.org/download/).

> **⚠️ Note**: version **`0.12.0`** is recommended.

Next, clone this repository and build the project using the command:

```bash
zig build -Doptimize=ReleaseFast
```

You can now connect **Victoire** to a **GUI** such as [Cute Chess](https://github.com/cutechess/cutechess) or directly run the engine with the command:

```bash
zig-out/bin/Victoire
```

## 🌟 Features

**Victoire** uses the [UCI](https://github.com/nomemory/uci-protocol-specification) protocol to communicate.

### 🎮 Available commands

The commands interpreted by the engine are listed below, more **UCI** protocol commands will be added in the future.

| **Commands**     | **Description**       | **Comments**                                      |
|------------------|-----------------------|---------------------------------------------------|
| **`uci`**        |                       |                                                   |
| **`ucinewgame`** | Initialize a new game | Reset transposition table                         |
| **`isready`**    |                       |                                                   |
| **`position`**   | Set the position      | Support `fen`, `startpos` and `moves`             |
| **`go`**         | Start the search      | See below for available options                   |
| **`go perft`**   | Start the perft test  | Usage: `go perft <depth>`                         |
| **`stop`**       | Stop the search       | Stop ponder thread                                |
| **`setoption`**  | Set an option         |                                                   |
| **`quit`**       | Quit the engine       | Can be used at any time                           |

**`go`** comand supports `movetime` (in ms), `depth` (in plies), `infinite`, `wtime`, `btime`, `winc`, `binc` and `movestogo`.

### ⚙️ Available options

Here is the list of currently available options. Use the command `setoption name <option name> value <value>` to change them.

| **Option**        | **Type** | **Description**                  | **Comments**                             |
|-------------------|----------|----------------------------------|------------------------------------------|
| **`Hash`**        | `spin`   | Transposition table size (in MB) | Will only take effect after `ucinewgame` |
| **`Ponder`**      | `check`  | Enable pondering                 | Take effect after next `go` command      |
| **`TimeControl`** | `check`  | Enable time control              | Take effect after next `go` command      |

### 📝 Example

```bash
uci # Prints available options and default values
setoption name Hash value 128
ucinewgame # Initialize a new game

position startpos moves e2e4 e7e5
# Or position fen rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -

go movetime 5000 depth 50 # Search for 5 seconds or 50 plies
```

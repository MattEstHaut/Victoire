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

| **Commands**     | **Description**       | **Comments**                                      |
|------------------|-----------------------|---------------------------------------------------|
| **`uci`**        |                       |                                                   |
| **`ucinewgame`** | Initialize a new game | Reset transposition table                         |
| **`isready`**    |                       |                                                   |
| **`position`**   | Set the position      | Support `fen`, `startpos` and `moves`             |
| **`go`**         | Start the search      | Support `movetime` (in ms) and `depth` (in plies) |
| **`stop`**       | Stop the search       | Stop ponder thread                                |
| **`setoption`**  | Set an option         |                                                   |
| **`quit`**       | Quit the engine       |                                                   |

### ⚙️ Available options

| **Option**   | **Type** | **Description**                  |
|--------------|----------|----------------------------------|
| **`Hash`**   | `spin`   | Transposition table size (in MB) |
| **`Ponder`** | `check`  | Enable pondering                 |

> **⚠️ Note**: changing the value of `hash` will only take effect after the `ucinewgame` command.

### 📝 Example

```bash
uci # Prints available options and default values
setoption name Hash value 128
ucinewgame # Initialize a new game

position startpos moves e2e4 e7e5
# Or position fen rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -

go movetime 5000 depth 50 # Search for 5 seconds or 50 plies
```

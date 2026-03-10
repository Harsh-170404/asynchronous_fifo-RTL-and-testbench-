# asynchronous_fifo-RTL-and-testbench

# Asynchronous FIFO — RTL Design & Verification (SystemVerilog)

A complete **CDC-safe Asynchronous FIFO** implementation with a **transaction-based SystemVerilog verification environment** built from scratch.

The project focuses on handling **clock-domain crossing (CDC)** challenges such as pointer synchronization, Gray-code conversion, and correct full/empty detection across independent clock domains.

---

## Key Features

- CDC-safe **Asynchronous FIFO architecture**
- **Gray-code pointer synchronization**
- Separate **read/write clock domains**
- Correct **full and empty flag generation**
- **Dual-port RAM based FIFO storage**
- Layered **transaction-based verification environment**
- Directed and **constrained-random testing**
- **Scoreboard-based data integrity checking**

---

## Design Architecture

The RTL design is organized into modular components:

- **Two-Flop Synchronizers** for pointer CDC
- **Write Controller**
  - Binary → Gray pointer conversion
  - Write pointer update logic
- **Read Controller**
  - Read pointer management
- **Status Logic**
  - Full and empty flag detection
- **Dual-Port RAM**
  - FIFO storage
- **Top-Level FIFO Wrapper**
  - Clean read/write interface integration

---

## Verification Architecture

The verification environment follows a **UVM-inspired layered approach implemented in pure SystemVerilog**.

Components include:

- **Transaction Class** – Defines FIFO operations
- **Generator** – Produces directed and randomized sequences
- **Driver** – Converts transactions into DUT stimulus
- **Monitor** – Observes read/write activity
- **Scoreboard** – Maintains expected data queue and checks ordering

Communication between components uses **mailboxes**, and the DUT connects via a **SystemVerilog interface with modports and clocking blocks**.

---

## Verification Scenarios

The design was validated with multiple test scenarios:

1. Reset synchronization across clock domains  
2. Basic write/read data integrity  
3. Sequential write bursts and ordered reads  
4. FIFO overflow protection  
5. FIFO underflow protection  
6. Constrained-random traffic testing  
7. Pointer wrap-around validation  
8. Mid-operation reset recovery  
9. Simultaneous read/write operation  

---

## Key Design Insight

A direct comparison between the **registered write pointer** and the **synchronized read pointer** causes the `full` flag to assert **one cycle late**.

The correct implementation compares the **next write Gray pointer** with the synchronized read pointer, ensuring the `full` condition asserts exactly on the final valid write.

---

## Skills Demonstrated

- Asynchronous FIFO architecture
- Clock Domain Crossing (CDC) design
- SystemVerilog RTL development
- Transaction-based verification
- Constrained-random testing
- Scoreboard-based functional verification

---

## Technologies

- **SystemVerilog**
- **RTL Design**
- **Digital Design Verification**
- **CDC Design Techniques**

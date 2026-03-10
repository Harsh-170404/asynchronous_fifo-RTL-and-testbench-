# asynchronous_fifo-RTL-and-testbench

This project implements and verifies a CDC-safe Asynchronous FIFO using SystemVerilog.
The focus of the project is not only the RTL design but also building a layered verification environment capable of stressing corner cases commonly encountered in clock domain crossing systems.

Asynchronous FIFOs are widely used in digital systems to transfer data between independent clock domains. While the concept is simple, the implementation requires careful handling of pointer synchronization, flag generation, and CDC safety to prevent data corruption.

This repository contains the full RTL design, verification environment, and simulation testcases used to validate the design.

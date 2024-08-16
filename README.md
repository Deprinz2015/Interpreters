# Mono Repo for Interpreters

This is a collection of my attempts at building my own Interpreters.

Most of the interpreters here will be based the book [Crafting Interpreters](https://craftinginterpreters.com/index.html)

## plox

plox is the first implementation of the Lox Language from "Crafting Interpreters". It is the Java implementation written in PHP.
It is the first attempt at a basic Tree-Walking Interpreter. It works by building an AST from the source code and then walking
the tree and executing the instructions from the nodes directly.

## zlox

zlox is the second implementation, inspired by the C implementation from "Crafting Interpreters". It is written in Zig.
It is a Byte-Code Virtual Machine. It works by translating the Source Code into Byte-Code specific to this Stack-Based VM.
I sticked mostly to the book, but skipped implementing the OOP Part. Instead i tried myself at implementing an array-like structure
myself. 


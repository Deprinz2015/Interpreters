<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Stmt\FunctionStmt;

class LoxFunction implements LoxCallable
{
    public function __construct(
        private FunctionStmt $declaration,
    )
    { }

    public function call(Interpreter $interpreter, array $arguments) { }

    public function arity(): int { }
}

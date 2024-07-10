<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Stmt\FunctionStmt;

class LoxFunction implements LoxCallable
{
    public function __construct(
        private FunctionStmt $declaration,
    ) {
    }

    public function call(Interpreter $interpreter, array $arguments)
    {
        $env = new Environment($interpreter->globals);
        for ($i = 0; $i < count($this->declaration->params); ++$i) {
            $env->define($this->declaration->params[$i]->lexeme, $arguments[$i]);
        }

        try {
            $interpreter->executeBlock($this->declaration->body, $env);
        } catch (ReturnValue $value) {
            return $value->value;
        }

        return null;
    }

    public function arity(): int
    {
        return count($this->declaration->params);
    }

    public function __toString()
    {
        return "<fn {$this->declaration->name->lexeme}>";
    }
}

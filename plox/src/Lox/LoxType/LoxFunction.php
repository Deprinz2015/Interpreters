<?php

namespace Nkoll\Plox\Lox\LoxType;

use Nkoll\Plox\Lox\Environment;
use Nkoll\Plox\Lox\Interpreter;
use Nkoll\Plox\Lox\ReturnValue;
use Nkoll\Plox\Lox\Stmt\FunctionStmt;

class LoxFunction implements LoxCallable
{
    public function __construct(
        private FunctionStmt $declaration,
        private Environment $closure,
        private bool $isInitializer,
    ) {
    }

    public function bind(LoxInstance $instance): LoxFunction {
        $env = new Environment($this->closure);
        $env->define("this", $instance);
        return new LoxFunction($this->declaration, $env, $this->isInitializer);
    }

    public function call(Interpreter $interpreter, array $arguments)
    {
        $env = new Environment($this->closure);
        for ($i = 0; $i < count($this->declaration->params); ++$i) {
            $env->define($this->declaration->params[$i]->lexeme, $arguments[$i]);
        }

        try {
            $interpreter->executeBlock($this->declaration->body, $env);
        } catch (ReturnValue $value) {
            if ($this->isInitializer) {
                return $this->closure->getAt(0, "this");
            }
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

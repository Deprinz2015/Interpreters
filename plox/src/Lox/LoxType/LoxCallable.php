<?php

namespace Nkoll\Plox\Lox\LoxType;

use Nkoll\Plox\Lox\Interpreter;

interface LoxCallable 
{
    /**
     * @param Interpreter $interpreter 
     * @param array $arguments 
     * @return mixed 
     */
    public function call(Interpreter $interpreter, array $arguments);

    public function arity(): int;
}

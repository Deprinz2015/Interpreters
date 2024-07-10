<?php

namespace Nkoll\Plox\Lox;

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

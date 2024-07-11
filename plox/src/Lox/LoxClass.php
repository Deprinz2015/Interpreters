<?php

namespace Nkoll\Plox\Lox;

class LoxClass implements LoxCallable
{
    public function __construct(
        public string $name,
    ) {
    }

    public function call(Interpreter $interpreter, array $arguments)
    {
        $instance = new LoxInstance($this);
        return $instance;
    }

    public function arity(): int
    {
        return 0;
    }

    public function __toString()
    {
        return $this->name;
    }
}

<?php

namespace Nkoll\Plox\Lox;

class LoxClass implements LoxCallable
{

    /**
     * @param string $name 
     * @param array<string, LoxFunction> $methods 
     * @return void 
     */
    public function __construct(
        public string $name,
        public array $methods,
    ) {
    }

    public function findMethod(string $name) {
        if (key_exists($name, $this->methods)) {
            return $this->methods[$name];
        }

        return null;
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

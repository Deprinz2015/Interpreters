<?php

namespace Nkoll\Plox\Lox;

class LoxClass implements LoxCallable
{
    /**
     * @param array<string, LoxFunction> $methods
     *
     * @return void
     */
    public function __construct(
        public string $name,
        public ?LoxClass $superclass,
        public array $methods,
    ) {
    }

    public function findMethod(string $name): ?LoxFunction
    {
        if (key_exists($name, $this->methods)) {
            return $this->methods[$name];
        }

        if ($this->superclass) {
            return $this->superclass->findMethod($name);
        }

        return null;
    }

    public function call(Interpreter $interpreter, array $arguments)
    {
        $instance = new LoxInstance($this);
        $init = $this->findMethod('init');
        if ($init) {
            $init->bind($instance)->call($interpreter, $arguments);
        }

        return $instance;
    }

    public function arity(): int
    {
        $init = $this->findMethod('init');
        if (!$init) {
            return 0;
        }

        return $init->arity();
    }

    public function __toString()
    {
        return $this->name;
    }
}

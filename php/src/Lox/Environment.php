<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\RuntimeError;

class Environment
{
    /** @var array<string, mixed> */
    private array $values = [];
    private ?Environment $enclosing;

    public function __construct(?Environment $enclosing = null)
    {
        $this->enclosing = $enclosing;
    }

    public function define(string $key, mixed $value): void
    {
        $this->values[$key] = $value;
    }

    public function get(Token $name): mixed
    {
        if(key_exists($name->lexeme, $this->values)) {
            return $this->values[$name->lexeme];
        }

        if ($this->enclosing !== null) {
            return $this->enclosing->get($name);
        }

        throw new RuntimeError($name, "Undefined variable '{$name->lexeme}'.");
    }

    public function assign(Token $name, mixed $value): void
    {
        if(key_exists($name->lexeme, $this->values)) {
            $this->values[$name->lexeme] = $value;
            return;
        }

        if ($this->enclosing !== null) {
            $this->enclosing->assign($name, $value);
            return;
        }

        throw new RuntimeError($name, "Undefined variable '{$name->lexeme}'.");
    }
}

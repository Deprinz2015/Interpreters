<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\RuntimeError;

class Environment 
{
    private array $values;

    public function define(string $key, mixed $value): void {
        $this->values[$key] = $value;
    }

    public function get(Token $name): mixed {
        if(key_exists($name->lexeme, $this->values)) {
            return $this->values[$name->lexeme];
        }

        throw new RuntimeError($name, "Undefined variable '{$name->lexeme}'.");
    }
}

<?php

namespace Nkoll\Plox\Lox\LoxType;

use Nkoll\Plox\Lox\Error\RuntimeError;
use Nkoll\Plox\Lox\Token;

class LoxInstance
{
    private LoxClass $klass;
    private array $fields = [];

    public function __construct(
        LoxClass $klass,
    ) {
        $this->klass = $klass;
    }

    public function get(Token $name) {
        if (key_exists($name->lexeme, $this->fields)) {
            return $this->fields[$name->lexeme];
        }

        $method = $this->klass->findMethod($name->lexeme);
        if ($method) {
            return $method->bind($this);
        }

        throw new RuntimeError($name, "Undefined property {$name->lexeme}'.");
    }

    public function set(Token $name, $value) {
        $this->fields[$name->lexeme] = $value;
    }

    public function __toString()
    {
        return $this->klass->name . " instance";
    }
}

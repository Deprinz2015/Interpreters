<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\RuntimeError;

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

<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Enums\TokenType;

class Token
{
    public function __construct(
        public TokenType $type,
        public string $lexeme,
        public $literal,
        public int $line,
    ) {
    }

    public function __toString()
    {
        return $this->type->name . " " . $this->lexeme . " " . $this->literal;
    }
}

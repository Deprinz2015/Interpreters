<?php

namespace Nkoll\Plox\Lox;

use Exception;

class ReturnValue extends Exception
{
    public function __construct(
        public mixed $value,
    ) {
    }
}

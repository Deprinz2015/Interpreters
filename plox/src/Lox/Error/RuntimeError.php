<?php

namespace Nkoll\Plox\Lox\Error;

use Exception;
use Nkoll\Plox\Lox\Token;

class RuntimeError extends Exception
{
    public Token $token;

    public function __construct(
        Token $token,
        string $msg,
    )
    {
        $this->token = $token;
        $this->message = $msg;
    }
    
}

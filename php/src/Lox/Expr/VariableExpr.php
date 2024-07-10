<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class VariableExpr extends Expr
{
    public function __construct(
        public Token $name,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitVariableExpr($this);
    }
}

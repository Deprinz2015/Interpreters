<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class UnaryExpr extends Expr
{
    public function __construct(
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitUnaryExpr($this);
    }
}

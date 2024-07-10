<?php

namespace Nkoll\Plox\Lox;

class UnaryExpr extends Expr
{
    public function __construct(
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitUnaryExpr($this);
    }
}

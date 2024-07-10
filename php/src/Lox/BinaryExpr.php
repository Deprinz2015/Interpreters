<?php

namespace Nkoll\Plox\Lox;

class BinaryExpr extends Expr
{
    public function __construct(
        public Expr $left,
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitBinaryExpr($this);
    }
}

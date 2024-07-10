<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class BinaryExpr extends Expr
{
    public function __construct(
        public Expr $left,
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitBinaryExpr($this);
    }
}

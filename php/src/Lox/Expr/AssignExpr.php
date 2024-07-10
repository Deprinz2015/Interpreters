<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class AssignExpr extends Expr
{
    /**
     * @param Token $name
     * @param Expr $value
     */
    public function __construct(
        public Token $name,
        public Expr $value,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitAssignExpr($this);
    }
}

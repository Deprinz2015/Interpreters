<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class VariableExpr extends Expr
{
    /**
     * @param Token $name
     */
    public function __construct(
        public Token $name,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitVariableExpr($this);
    }
}

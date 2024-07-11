<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class ThisExpr extends Expr
{
    /**
     * @param Token $keyword
     */
    public function __construct(
        public Token $keyword,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitThisExpr($this);
    }
}

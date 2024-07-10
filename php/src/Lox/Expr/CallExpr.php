<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class CallExpr extends Expr
{
    /**
     * @param Expr $callee
     * @param Token $paren
     * @param Expr[] $arguments
     */
    public function __construct(
        public Expr $callee,
        public Token $paren,
        public array $arguments,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitCallExpr($this);
    }
}

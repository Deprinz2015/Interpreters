<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Token;
use Nkoll\Plox\Lox\Expr\Expr;

class ReturnStmt extends Stmt
{
    /**
     * @param Token $keyword
     * @param ?Expr $value
     */
    public function __construct(
        public Token $keyword,
        public ?Expr $value,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitReturnStmt($this);
    }
}

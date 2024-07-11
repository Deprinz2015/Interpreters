<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Token;
use Nkoll\Plox\Lox\Expr\VariableExpr;
use Nkoll\Plox\Lox\Stmt\FunctionStmt;

class ClassStmt extends Stmt
{
    /**
     * @param Token $name
     * @param ?VariableExpr $superclass
     * @param FunctionStmt[] $methods
     */
    public function __construct(
        public Token $name,
        public ?VariableExpr $superclass,
        public array $methods,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitClassStmt($this);
    }
}

<?php

namespace Nkoll\Plox\Lox\Stmt;

class BlockStmt extends Stmt
{
    /**
     * @param Stmt[] $statements
     */
    public function __construct(
        public array $statements,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitBlockStmt($this);
    }
}

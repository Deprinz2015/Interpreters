<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Token;

class FunctionStmt extends Stmt
{
    /**
     * @param Token $name
     * @param Token[] $params
     * @param Stmt[] $body
     */
    public function __construct(
        public Token $name,
        public array $params,
        public array $body,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitFunctionStmt($this);
    }
}

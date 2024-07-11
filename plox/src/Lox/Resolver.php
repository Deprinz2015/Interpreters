<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Expr\AssignExpr;
use Nkoll\Plox\Lox\Expr\BinaryExpr;
use Nkoll\Plox\Lox\Expr\CallExpr;
use Nkoll\Plox\Lox\Expr\Expr;
use Nkoll\Plox\Lox\Expr\ExprVisitor;
use Nkoll\Plox\Lox\Expr\GetExpr;
use Nkoll\Plox\Lox\Expr\GroupingExpr;
use Nkoll\Plox\Lox\Expr\LiteralExpr;
use Nkoll\Plox\Lox\Expr\LogicalExpr;
use Nkoll\Plox\Lox\Expr\SetExpr;
use Nkoll\Plox\Lox\Expr\ThisExpr;
use Nkoll\Plox\Lox\Expr\UnaryExpr;
use Nkoll\Plox\Lox\Expr\VariableExpr;
use Nkoll\Plox\Lox\Stmt\BlockStmt;
use Nkoll\Plox\Lox\Stmt\ClassStmt;
use Nkoll\Plox\Lox\Stmt\ExpressionStmt;
use Nkoll\Plox\Lox\Stmt\FunctionStmt;
use Nkoll\Plox\Lox\Stmt\IfStmt;
use Nkoll\Plox\Lox\Stmt\ReturnStmt;
use Nkoll\Plox\Lox\Stmt\Stmt;
use Nkoll\Plox\Lox\Stmt\StmtVisitor;
use Nkoll\Plox\Lox\Stmt\VarStmt;
use Nkoll\Plox\Lox\Stmt\WhileStmt;
use Nkoll\Plox\PloxCommand;
use SplStack;

class Resolver implements ExprVisitor, StmtVisitor
{
    private Interpreter $interpreter;
    private SplStack $scopes;
    private FunctionType $currentFunction = FunctionType::NONE;
    private ClassType $currentClass = ClassType::NONE;

    public function __construct(Interpreter $interpreter)
    {
        $this->interpreter = $interpreter;
        $this->scopes = new SplStack();

    }

    public function visitBinaryExpr(BinaryExpr $expr)
    {
        $this->resolve($expr->left);
        $this->resolve($expr->right);
    }

    public function visitCallExpr(CallExpr $expr)
    {
        $this->resolve($expr->callee);

        foreach ($expr->arguments as $arg) {
            $this->resolve($arg);
        }
    }

    public function visitGetExpr(GetExpr $expr)
    {
        $this->resolve($expr->object);
    }

    public function visitGroupingExpr(GroupingExpr $expr)
    {
        $this->resolve($expr->expression);
    }

    public function visitLiteralExpr(LiteralExpr $expr)
    {
        // noop
    }

    public function visitLogicalExpr(LogicalExpr $expr)
    {
        $this->resolve($expr->left);
        $this->resolve($expr->right);
    }

    public function visitSetExpr(SetExpr $expr)
    {
        $this->resolve($expr->object);
        $this->resolve($expr->value);
    }

    public function visitThisExpr(ThisExpr $expr)
    {
        if ($this->currentClass === ClassType::NONE) {
            PloxCommand::errorToken($expr->keyword, "Can't use 'this' outside of a class.");
            return;
        }
        $this->resolveLocal($expr, $expr->keyword);
    }

    public function visitUnaryExpr(UnaryExpr $expr)
    {
        $this->resolve($expr->right);
    }

    public function visitExpressionStmt(ExpressionStmt $stmt)
    {
        $this->resolve($stmt->expression);
    }

    public function visitIfStmt(IfStmt $stmt)
    {
        $this->resolve($stmt->condition);
        $this->resolve($stmt->thenBranch);
        if ($stmt->elseBranch) {
            $this->resolve($stmt->elseBranch);
        }
    }

    public function visitReturnStmt(ReturnStmt $stmt)
    {
        if ($this->currentFunction === FunctionType::NONE) {
            PloxCommand::errorToken($stmt->keyword, "Can't return from top-level code.");
        }

        if ($this->currentFunction === FunctionType::INITIALIZER) {
            PloxCommand::errorToken($stmt->keyword, "Can't return from initializer.");
        }

        if ($stmt->value) {
            $this->resolve($stmt->value);
        }
    }

    public function visitWhileStmt(WhileStmt $stmt)
    {
        $this->resolve($stmt->condition);
        $this->resolve($stmt->body);
    }

    public function visitBlockStmt(BlockStmt $stmt)
    {
        $this->beginScope();
        $this->resolveAll($stmt->statements);
        $this->endScope();
    }

    public function visitClassStmt(ClassStmt $stmt)
    {
        $enclosing = $this->currentClass;
        $this->currentClass = ClassType::CLASS_TYPE;
        $this->declare($stmt->name);
        $this->define($stmt->name);

        if ($stmt->superclass) {
            if ($stmt->superclass->name->lexeme === $stmt->name->lexeme) {
                PloxCommand::errorToken($stmt->superclass->name, "A class cannot inherit from itself.");
            }
            $this->resolve($stmt->superclass);
        }

        $this->beginScope();
        $scope = $this->scopes->pop();
        $scope["this"] = true;
        $this->scopes->push($scope);

        foreach($stmt->methods as $method) {
            $declaration = FunctionType::METHOD;
            if ($method->name->lexeme === "init") {
                $declaration = FunctionType::INITIALIZER;
            }
            $this->resolveFunction($method, $declaration);
        }

        $this->endScope();

        $this->currentClass = $enclosing;
    }

    public function visitVarStmt(VarStmt $stmt)
    {
        $this->declare($stmt->name);
        if ($stmt->initializer) {
            $this->resolve($stmt->initializer);
        }
        $this->define($stmt->name);
    }

    public function visitVariableExpr(VariableExpr $expr)
    {
        if (!$this->scopes->isEmpty() && ($this->scopes->top()[$expr->name->lexeme] ?? null) === false) {
            var_dump($this->scopes);
            PloxCommand::errorToken($expr->name, "Can't read local variable in its own initializer.");
        }

        $this->resolveLocal($expr, $expr->name);
    }

    public function visitAssignExpr(AssignExpr $expr)
    {
        $this->resolve($expr->value);
        $this->resolveLocal($expr, $expr->name);
    }

    public function visitFunctionStmt(FunctionStmt $stmt)
    {
        $this->declare($stmt->name);
        $this->define($stmt->name);

        $this->resolveFunction($stmt, FunctionType::FUNCTION);
    }


    //--------------------------------------------------------------------------------------

    public function resolveAll(array $statements)
    {
        foreach($statements as $stmt) {
            $this->resolve($stmt);
        }
    }

    /**
     * @param Expr|Stmt $statement
     * @return void
     */
    private function resolve($statement)
    {
        $statement->accept($this);
    }

    private function resolveFunction(FunctionStmt $function, FunctionType $functionType)
    {
        $enclosingFunc = $this->currentFunction;
        $this->currentFunction = $functionType;

        $this->beginScope();
        foreach($function->params as $param) {
            $this->declare($param);
            $this->define($param);
        }
        $this->resolveAll($function->body);
        $this->endScope();

        $this->currentFunction = $enclosingFunc;
    }

    private function beginScope()
    {
        $this->scopes->push([]);
    }

    private function endScope()
    {
        $this->scopes->pop();
    }

    private function declare(Token $name)
    {
        if ($this->scopes->isEmpty()) {
            return;
        }

        $scope = $this->scopes->pop();
        if (key_exists($name->lexeme, $scope)) {
            PloxCommand::errorToken($name, "Already a variable with this name in this scope.");
        }
        $scope[$name->lexeme] = false;
        $this->scopes->push($scope);
    }

    private function define(Token $name)
    {
        if ($this->scopes->isEmpty()) {
            return;
        }

        $scope = $this->scopes->pop();
        $scope[$name->lexeme] = true;
        $this->scopes->push($scope);
    }

    private function resolveLocal(Expr $expr, Token $name)
    {
        for($depth = 0; $depth < $this->scopes->count(); $depth++) {
            if (key_exists($name->lexeme, $this->scopes[$depth])) {
                $this->interpreter->resolve($expr, $depth);
                return;
            }
        }
    }
}

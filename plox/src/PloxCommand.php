<?php

namespace Nkoll\Plox;

use Nkoll\Plox\Lox\Error\RuntimeError;
use Nkoll\Plox\Lox\Interpreter;
use Nkoll\Plox\Lox\Parser;
use Nkoll\Plox\Lox\Resolver;
use Nkoll\Plox\Lox\Scanner;
use Nkoll\Plox\Lox\Token;
use Nkoll\Plox\Lox\TokenType;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

class PloxCommand extends Command
{
    private Interpreter $interpreter;

    public static bool $hadError = false;
    public static bool $hadRuntimeError = false;

    private SymfonyStyle $io;

    public function configure()
    {
        $this->setName('run')
            ->setDescription('PHP Implementation of the Lox Interpreter')
            ->addArgument('file', InputArgument::OPTIONAL, 'Path to the .lox file to be interpreted');
    }

    public function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->interpreter = new Interpreter();
        $this->io = new SymfonyStyle($input, $output);

        if (($path = $input->getArgument('file'))) {
            return $this->runFile($path);
        }
        return $this->runPrompt();
    }

    private function runFile(string $path): int
    {
        $script = file_get_contents($path);
        $this->runScript($script);

        if (self::$hadError || self::$hadRuntimeError) {
            return Command::FAILURE;
        }
        return Command::SUCCESS;
    }

    private function runPrompt(): int
    {
        while(true) {
            $script = $this->io->ask('plox');
            if ($script == null) {
                break;
            }
            $this->runScript($script);
            self::$hadError = false;
        }

        return Command::SUCCESS;
    }

    private function runScript(string $script): void
    {
        $scanner = new Scanner($script);
        $tokens = $scanner->scanTokens();
        $parser = new Parser($tokens);
        $stmts = $parser->parse();

        if (self::$hadError) {
            return;
        }

        $resolver = new Resolver($this->interpreter);
        $resolver->resolveAll($stmts);

        if (self::$hadError) {
            return;
        }

        $this->interpreter->interpret($stmts);
    }

    public static function error(int $line, string $msg): void
    {
        self::report($line, "", $msg);
    }

    public static function errorToken(Token $token, string $msg): void
    {
        if ($token->type === TokenType::EOF) {
            self::report($token->line, " at end", $msg);
        } else {
            self::report($token->line, " at '{$token->lexeme}'", $msg);
        }
    }

    public static function runtimeError(RuntimeError $e): void {
        echo $e->getMessage() . "\n[line {$e->token->line}]" . PHP_EOL;
        self::$hadRuntimeError = true;
    }

    private static function report(int $line, string $where, string $msg): void
    {
        echo "[line $line] Error $where: $msg" . PHP_EOL;
        self::$hadError = true;
    }
}

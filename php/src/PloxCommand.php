<?php

namespace Nkoll\Plox;

use Nkoll\Plox\Lox\Scanner;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

class PloxCommand extends Command
{
    public static bool $hadError = false;

    private SymfonyStyle $io;

    public function configure()
    {
        $this->setName('run')
            ->setDescription('PHP Implementation of the Lox Interpreter')
            ->addArgument('file', InputArgument::OPTIONAL, 'Path to the .lox file to be interpreted');
    }

    public function execute(InputInterface $input, OutputInterface $output): int
    {
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

        if (self::$hadError) {
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

        foreach ($tokens as $token) {
            echo $token . PHP_EOL;
        }
    }

    public static function error(int $line, string $msg): void {
        self::report($line, "", $msg);
    }

    private static function report(int $line, string $where, string $msg): void {
        echo "[line $line] Error $where: $msg" . PHP_EOL;
        self::$hadError = true;
    }
}

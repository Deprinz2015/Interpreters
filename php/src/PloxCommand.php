<?php

namespace Nkoll\Plox;

use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

class PloxCommand extends Command
{
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
            $this->runFile($path);
        }
        else {
            $this->runPrompt();
        }

        return Command::SUCCESS;
    }

    private function runFile(string $path): void 
    {
        $script = file_get_contents($path);
        $this->runScript($script);
    }

    private function runPrompt(): void
    {
        while(true) {
            $script = $this->io->ask('plox');
            if ($script == null) {
                break;
            }
            $this->runScript($script);
        }
    }

    private function runScript(string $script): void 
    {
    }
}

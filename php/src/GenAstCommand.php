<?php

namespace Nkoll\Plox;

use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

class GenAstCommand extends Command
{
    private const asts = [
        "Expr" => [
            "Assign   : Token name, Expr value",
            "Binary   : Expr left, Token operator, Expr right",
            "Grouping : Expr expression",
            "Literal  : mixed value",
            "Unary    : Token operator, Expr right",
            "Variable : Token name",
        ],
        "Stmt" => [
            "Block      : Stmt[] statements",
            "Expression : Expr expression",
            "Print      : Expr expression",
            "Var        : Token name, ?Expr initializer",
        ],
    ];

    public function configure()
    {
        $this->setName('ast')
            ->setDescription('PHP Implementation of the Lox Interpreter')
            ->addArgument('output_dir', InputArgument::REQUIRED, 'Path to the .lox file to be interpreted');
    }

    public function execute(InputInterface $input, OutputInterface $output): int
    {
        $outputDir = $input->getArgument('output_dir');
        if (str_ends_with($outputDir, "/")) {
            $outputDir = substr($outputDir, 0, strlen($outputDir) - 1);
        }

        foreach(self::asts as $base => $types) {
            $this->defineAst($outputDir, $base, $types);
        }

        return Command::SUCCESS;
    }

    private function defineAst(string $outputDir, string $baseName, array $types): void
    {
        $outputDir = "$outputDir/$baseName";

        if (!file_exists($outputDir)) {
            mkdir($outputDir);
        }

        $path = "$outputDir/$baseName.php";

        $content = "<?php

namespace Nkoll\Plox\Lox\\$baseName;

abstract class $baseName
{
    abstract public function accept({$baseName}Visitor \$visitor);
}
";

        file_put_contents($path, $content);

        $this->defineVisitor($outputDir, $baseName, $types);

        foreach ($types as $type) {
            [$classname, $fields] = explode(':', $type);
            $classname = trim($classname);
            $fields = trim($fields);
            $this->defineType($outputDir, $baseName, $classname, $fields);
        }

    }

    private function defineVisitor(string $outputDir, string $basename, array $types): void
    {
        $path = "$outputDir/{$basename}Visitor.php";

        $content = "<?php

namespace Nkoll\Plox\Lox\\$basename;

interface {$basename}Visitor
{
";
        foreach($types as $type) {
            $typeName = trim(explode(':', $type)[0]) . $basename;
            $varName = strtolower($basename);
            $content .= "    public function visit$typeName($typeName \$$varName);" . PHP_EOL;
        }

        $content .= "}";
        file_put_contents($path, $content);
    }

    /**
     * @param string $outputDir 
     * @param string $basename 
     * @param string $classname 
     * @param string $fields 
     * @return void 
     */
    private function defineType(string $outputDir, string $basename, string $classname, string $fields): void
    {
        $fields = explode(', ', $fields);

        $neededTypes = [];
        $typeHints = [];
        $fields = array_map(function ($field) use (&$neededTypes, &$typeHints, $basename) {
            [$typeDef, $name] = explode(' ', $field);
            $typeHints[] = "     * @param $typeDef \$$name";

            $nullable = str_starts_with($typeDef, '?');
            $array = str_ends_with($typeDef, '[]');

            $type = $nullable ? substr($typeDef, 1) : $typeDef;
            if ($array) {
                $type = $array ? substr($type, 0, strlen($type) - 2) : $type;
                $typeDef = 'array';
            }

            if (ctype_upper($type[0]) && $type !== $basename) {
                $import = $type;
                if (in_array($type, array_keys(self::asts))) {
                    $import = "$type\\$type";
                }
                $neededTypes[] = $import;
            }

            return "        public $typeDef \$$name,";
        }, $fields);
        $fields = implode(PHP_EOL, $fields);
        $neededTypes = array_unique($neededTypes);

        $neededTypes = array_map(function (string $type) {
            return "use Nkoll\Plox\Lox\\$type;";
        }, $neededTypes);
        $neededTypes = implode(PHP_EOL, $neededTypes);
        $typeHints = implode(PHP_EOL, $typeHints);
        $typeHints = "/**\n$typeHints\n     */";
        if ($neededTypes !== "") {
            $neededTypes = "\n$neededTypes\n";
        }

        $path = "$outputDir/$classname$basename.php";

        $content = "<?php

namespace Nkoll\Plox\Lox\\$basename;
$neededTypes
class $classname$basename extends $basename
{
    $typeHints
    public function __construct(
$fields
    ) { }

    public function accept({$basename}Visitor \$visitor)
    {
        return \$visitor->visit$classname$basename(\$this);
    }
}
";

        file_put_contents($path, $content);
    }
}

// One-off transform: add explicit onDelete/onUpdate (NoAction) to every @relation
// that lacks them, so the schema satisfies SQL Server referential-action rules.
const fs = require('fs')
const path = 'D:/GYM/Backend/prisma/schema.prisma'
let src = fs.readFileSync(path, 'utf8')

src = src.replace(/@relation\(([^)]*)\)/g, (m, args) => {
  const hasDelete = /onDelete\s*:/.test(args)
  const hasUpdate = /onUpdate\s*:/.test(args)
  let add = ''
  if (!hasDelete) add += ', onDelete: NoAction'
  if (!hasUpdate) add += ', onUpdate: NoAction'
  return `@relation(${args}${add})`
})

fs.writeFileSync(path, src)
console.log('relations updated')

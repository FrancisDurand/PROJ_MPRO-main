using CPLEX
using JuMP

"""
Résoudre instance par plan coupants :

Argument
- n, s, t, S, d1, d2, p, ph, d, D : donnés du problème

Return
- true si le problème est résolu de manière optimale
- x : tableau de variables bidimensionnelles tel que x[i, j] = 1 si on passe de i à j
- valeur de la fonction objectif
- temps de résolution en secondes
- nombre de coupes ajoutées
"""

function plan_coupants(n, s, t, S, d1, d2, p, ph, d, D)

    # Démarrer un chronomètre
    start = time()

    # Définir la fonction objective et les contraintes du programme maître

    m = JuMP.Model(CPLEX.Optimizer)
    # Variables du modèle
    @variable(m, x[1:n, 1:n], Bin)
    @variable(m, y[1:n], Bin)
    @variable(m, z >= 0)

    # Contraintes
    @constraint(m, sum(x[s,j] for j in 1:n) - sum(x[j,s] for j in 1:n) == 1) # le chemin quitte s
    @constraint(m, sum(x[t,j] for j in 1:n) - sum(x[j,t] for j in 1:n) == -1) # le chemin arrive en t

    for v in 1:n
        if v != s && v != t
            @constraint(m, sum(x[i, v] for i = 1:n) == sum(x[v, j] for j = 1:n)) # conservation du flot
        end
        if v!=t
            @constraint(m, y[v] == sum(x[v,j] for j in 1:n)) # lien entre les variable x et y
        end
    end

    @constraint(m, y[t] == sum(x[i,t] for i in 1:n)) # lien entre les variables x et y_t

    # Contrainte d'objectif (c'est à dire U^1* = {dij1 = dij})
    @constraint(m, z >= sum(p[v]*y[v] for v in 1:n))

    # Contrainte de poids (c'est à dire U^2* = {pi2 = pi})
    @constraint(m, z >= sum(d[i,j]*x[i,j] for i in 1:n, j in 1:n))

    # Fonction objective
    @objective(m, Min, z)

    # Résoudre le programme maître initial
    optimize!(m)

    current_x = value.(x)
    current_y = value.(y)
    current_z = value(z)


    # Boucle principale du problème d'optimisation par plan coupant
    for iteration in 1:100  #Limite de 100 plans coupants ajoutés pour l'instant
        println("\nIteration $iteration:")

        
            # Vérifier si l'optimisation a réussi
        if termination_status(m) == MOI.OPTIMAL
            println("x: ", current_x)
            println("y: ", current_y)
            println("Valeur du programme avec les coupes actuelles: ", current_z)
        else
            println("L'optimisation n'a pas abouti.")
        end
        

        # Résoudre le sous problème liéé à U^1
        esclave_1 = JuMP.Model(CPLEX.Optimizer)
            # Variables du modèle
            @variable(esclave_1, 0 <= delta1[1:n, 1:n])
            for i in 1:n
                for j in 1:n
                    @constraint(esclave_1, delta1[i, j] <= D[i, j])
                end
            end
            @constraint(esclave_1, sum(delta1[i,j] for i in 1:n, j in 1:n) <= d1)
            
            @objective(esclave_1, Max, sum(current_x[i,j]*d[i,j] for i in 1:n, j in 1:n) + sum(current_x[i,j]*d[i,j]delta1[i,j] for i in 1:n, j in 1:n)) 
        optimize!(esclave_1)
        current_delta1 = value.(delta1)
        current_z1 = objective_value(esclave_1)

        
        # Résoudre le sous problème liéé à U^2
        esclave_2 = JuMP.Model(CPLEX.Optimizer)
            # Variables du modèle
            @variable(esclave_2, 0 <= delta2[1:n] <= 2)
            @constraint(esclave_2, sum(delta2[v] for v in 1:n) <= d1)
            
            @objective(esclave_2, Max, sum(current_y[v]*p[v] for v in 1:n) + sum(current_y[v]*ph[v]*delta2[v] for v in 1:n)) 
        optimize!(esclave_2)
        current_delta2 = value.(delta2)
        current_z2 = objective_value(esclave_2)

       

        # Verifier si on est optimal

        if current_z == current_z1 && current_z2 <= S 
            return true, current_x, JuMP.objective_value(m), time() - start

        else
            # Ajouter la coupe liéé à U^1
            @constraint(m, z >= sum(d[i,j]*x[i,j] for i in 1:n, j in 1:n) + sum(d[i,j]*current_delta1[i,j]*x[i,j] for i in 1:n, j in 1:n))

            # Ajouter la coupe liéé à U^2
            @constraint(m, sum(y[v]*p[v] for v in 1:n) + sum(y[v]*ph[v]*current_delta2[v] for v in 1:n) <= S)
        end

        # Résoudre le programme maître avec la nouvelle coupe
        optimize!(m)

        # Récupérer les valeurs optimales des variables
        current_x = value.(x)
        current_y = value.(y)
        current_z = value(z)


        # Afficher les résultats de l'itération actuelle
        # println("Objective value: ", objective_value(m))
        # println("x = ", current_x)
        # println("y = ", current_y)
    end

    return false, current_x, JuMP.objective_value(m), time() - start

end
inf = 99999999999

function heuristique_statique(n, s, t, S, p, d)
    start = time() # Démarrer un chronomètre

    # Initialisation des vecteurs qui seront utilisés
    visited = falses(n)
    accumulated_duration = inf * ones(Float64, n)
    accumulated_weight = zeros(Int, n)
    predecessors = zeros(Int, n)

    accumulated_duration[s] = 0
    accumulated_weight[s] = p[s]

    for _ in 1:n
        # Trouver le sommet non visité avec la plus petite duration actuelle
        u = argmin(accumulated_duration .+ visited .* inf)
        
        visited[u] = true

        # Si le sommet trouvé est la destination, arrêtez la boucle
        if u == t
            break
        end

        # Mise à jour les durations, poids et les prédécesseurs des voisins de u
        for v in 1:n
            # Si non visité
            if !visited[v]
                # Si :
                # 1. la nouvelle duration est inférieure à la duration actuelle et le nouveau poids ne dépassera pas S
                # ou
                # 2. la nouvelle duration est égale à la duration actuelle, mais le nouveau poids est inférieur à celui actuel
                if (d[u, v] + accumulated_duration[u])<accumulated_duration[v] && (p[v]+accumulated_weight[u])<= S || (d[u, v] + accumulated_duration[u])==accumulated_duration[v] && (p[v]+accumulated_weight[u])<accumulated_weight[v]
                    accumulated_duration[v] = d[u, v] + accumulated_duration[u]
                    predecessors[v] = u
                    accumulated_weight[v] = p[v] + accumulated_weight[u] 
                end
            end
        end
    end

    # Reconstruction du chemin si trouvé
    if predecessors[t] != 0
        path = [t]
        u = t
        while u != s
            u = predecessors[u]
            pushfirst!(path, u)
        end

    # Si non trouvé, minimiser le poids
    else
        print("non optimal")

        # Initialisation des vecteurs qui seront utilisés
        visited = falses(n)
        accumulated_duration = inf * ones(Float64, n)
        accumulated_weight = inf * ones(Float64, n)
        predecessors = zeros(Int, n)

        accumulated_duration[s] = 0
        accumulated_weight[s] = p[s]

        for _ in 1:n
            # Trouver le sommet non visité avec le plus petit poids actuel
            u = argmin(accumulated_weight .+ visited .* inf )
            
            visited[u] = true

            # Si le sommet trouvé est la destination, arrêtez la boucle
            if u == t
                break
            end

            # Mise à jour les durations, poids et les prédécesseurs des voisins de u
            for v in 1:n
                # Si non visité et l'arc (u,v) existe
                if !visited[v] && d[u,v]!= inf
                    # Si :
                    # 1. le nouveau poids est inférieur à l'actuel
                    # ou
                    # 2. si le nouveau poids est égal à l'actuel mais que la duration est plus petite
                    if (p[v]+accumulated_weight[u])<accumulated_weight[v] || (p[v]+accumulated_weight[u])<=accumulated_weight[v] && (d[u, v] + accumulated_duration[u])<accumulated_duration[v]
                        accumulated_duration[v] = d[u, v] + accumulated_duration[u]
                        predecessors[v] = u
                        accumulated_weight[v] = p[v] + accumulated_weight[u] 
                    end
                end
            end
        end

        # si le chemin n'est pas trouvé ou si nous dépassons le poids, aucune solution respectant le poids maximum
        if predecessors[t] == 0 || accumulated_weight[t] > S
            return false, [], [] , time()-start
        end

        # Reconstruction du chemin
        path = [t]
        u = t
        while u != s
            u = predecessors[u]
            pushfirst!(path, u)
        end
        
    end

    return true, path, accumulated_duration[t], time() - start
end
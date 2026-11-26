import java.util.*;

/**
 * Reference harness for the original Java implementation of ATLAS
 * (https://github.com/savastakan/atlas). It is compiled together with the
 * original Atlas.java / Graph.java / Edge.java / Util.java files and prints
 * the walk ATLAS produces so the Lua port can be compared against it.
 *
 * Output lines:  PATH=<comma separated edge labels>
 *                SUITE=<comma separated inputs, i.e. Atlas.getTestSuite>
 */
public class RefHarness {
    public static void main(String[] args) throws Exception {
        for (String file : args) {
            Graph g = new Util().toGraph(file);
            Atlas a = new Atlas();
            LinkedList<Integer> path = a.longestPath(g, g.getStarts().iterator().next());
            StringBuilder sb = new StringBuilder();
            for (Integer label : path) sb.append(sb.length() == 0 ? "" : ",").append(label);
            System.out.println("FILE=" + file);
            System.out.println("PATH=" + sb);
            System.out.println("SUITE=" + a.getTestSuite(g, path));
        }
    }
}

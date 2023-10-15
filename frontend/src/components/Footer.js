import {
    ButtonGroup,
    Container,
    IconButton,
    Stack,
    Text,
} from '@chakra-ui/react';
import { FaGithub, FaLinkedin, FaFeather } from 'react-icons/fa';
import { Logo } from '../Logo';

const Footer = () => (
    <Container
        as="footer"
        role="contentinfo"
        py={{ base: '12', md: '16' }}
        position="relative"
        bg="purple.500" // Set the background color of the footer to purple
        color="white" // Set text color to white for better contrast
    >
        <Stack
            spacing={{ base: '4', md: '5' }}
            position="absolute"
            bottom="-30"
            right="20"
        >
            <ButtonGroup variant="tertiary">
                <IconButton
                    as="a"
                    href="https://www.linkedin.com/in/pietro-zanotta-62613125b/"
                    aria-label="LinkedIn"
                    icon={<FaLinkedin />}
                />
                <IconButton
                    as="a"
                    href="https://github.com/ScipioneParmigiano/morgante-protocol"
                    aria-label="GitHub"
                    icon={<FaGithub />}
                />
                <IconButton
                    as="a"
                    href="https://amm.zanotp.com/"
                    aria-label="Blog"
                    icon={<FaFeather />}
                />
            </ButtonGroup>
        </Stack>
    </Container>
);

export default Footer;
